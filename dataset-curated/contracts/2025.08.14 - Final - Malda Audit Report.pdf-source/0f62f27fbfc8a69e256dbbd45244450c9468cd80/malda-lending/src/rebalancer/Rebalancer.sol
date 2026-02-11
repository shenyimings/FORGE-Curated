// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {IRoles} from "src/interfaces/IRoles.sol";
import {IBridge} from "src/interfaces/IBridge.sol";
import {IOperator} from "src/interfaces/IOperator.sol";
import {ImTokenMinimal, ImToken} from "src/interfaces/ImToken.sol";
import {IRebalancer, IRebalanceMarket} from "src/interfaces/IRebalancer.sol";

import {SafeApprove} from "src/libraries/SafeApprove.sol";

contract Rebalancer is IRebalancer {
    // ----------- STORAGE ------------
    IRoles public roles;
    uint256 public nonce;
    mapping(uint32 => mapping(uint256 => Msg)) public logs;
    mapping(address => bool) public whitelistedBridges;
    mapping(uint32 => bool) public whitelistedDestinations;
    mapping(address => bool) public allowedList;

    address public saveAddress;

    struct TransferInfo {
        uint256 size;
        uint256 timestamp;
    }

    mapping(uint32 => mapping(address => uint256)) public maxTransferSizes;
    mapping(uint32 => mapping(address => uint256)) public minTransferSizes;
    mapping(uint32 => mapping(address => TransferInfo)) public currentTransferSize;
    uint256 public transferTimeWindow;

    constructor(address _roles, address _saveAddress) {
        roles = IRoles(_roles);
        transferTimeWindow = 86400;
        saveAddress = _saveAddress;
    }

    // ----------- OWNER METHODS ------------
    function setAllowList(address[] calldata list, bool status) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert Rebalancer_NotAuthorized();

        uint256 len = list.length;
        for (uint256 i; i < len; i++) {
            allowedList[list[i]] = status;
        }
        emit AllowedListUpdated(list, status);
    }

    function setWhitelistedBridgeStatus(address _bridge, bool _status) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert Rebalancer_NotAuthorized();
        require(_bridge != address(0), Rebalancer_AddressNotValid());
        whitelistedBridges[_bridge] = _status;
        emit BridgeWhitelistedStatusUpdated(_bridge, _status);
    }

    function setWhitelistedDestination(uint32 _dstId, bool _status) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert Rebalancer_NotAuthorized();
        emit DestinationWhitelistedStatusUpdated(_dstId, _status);
        whitelistedDestinations[_dstId] = _status;
    }

    function saveEth() external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert Rebalancer_NotAuthorized();

        uint256 amount = address(this).balance;
        // no need to check return value
        (bool success, ) = saveAddress.call{value: amount}("");
        require(success, Rebalancer_RequestNotValid());
        emit EthSaved(amount);
    }

    function setMinTransferSize(uint32 _dstChainId, address _token, uint256 _limit) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert Rebalancer_NotAuthorized();
        minTransferSizes[_dstChainId][_token] = _limit;
        emit MinTransferSizeUpdated(_dstChainId, _token, _limit);
    }

    function setMaxTransferSize(uint32 _dstChainId, address _token, uint256 _limit) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_BRIDGE())) revert Rebalancer_NotAuthorized();
        maxTransferSizes[_dstChainId][_token] = _limit;
        emit MaxTransferSizeUpdated(_dstChainId, _token, _limit);
    }

    // ----------- VIEW METHODS ------------
    /**
     * @inheritdoc IRebalancer
     */
    function isBridgeWhitelisted(address bridge) external view returns (bool) {
        return whitelistedBridges[bridge];
    }

    /**
     * @inheritdoc IRebalancer
     */
    function isDestinationWhitelisted(uint32 dstId) external view returns (bool) {
        return whitelistedDestinations[dstId];
    }

    // ----------- EXTERNAL METHODS ------------
    /**
     * @inheritdoc IRebalancer
     */
    function sendMsg(address _bridge, address _market, uint256 _amount, Msg calldata _msg) external payable {
        // checks
        if (!roles.isAllowedFor(msg.sender, roles.REBALANCER_EOA())) revert Rebalancer_NotAuthorized();
        require(whitelistedBridges[_bridge], Rebalancer_BridgeNotWhitelisted());
        require(whitelistedDestinations[_msg.dstChainId], Rebalancer_DestinationNotWhitelisted());
        address _underlying = ImTokenMinimal(_market).underlying();
        require(_underlying == _msg.token, Rebalancer_RequestNotValid());

        // min transfer size check
        require(_amount > minTransferSizes[_msg.dstChainId][_msg.token], Rebalancer_TransferSizeMinNotMet());

        // max transfer size checks
        TransferInfo memory transferInfo = currentTransferSize[_msg.dstChainId][_msg.token];
        uint256 transferSizeDeadline = transferInfo.timestamp + transferTimeWindow;
        if (transferSizeDeadline < block.timestamp) {
            currentTransferSize[_msg.dstChainId][_msg.token] = TransferInfo(_amount, block.timestamp);
        } else {
            currentTransferSize[_msg.dstChainId][_msg.token].size += _amount;
        }

        uint256 _maxTransferSize = maxTransferSizes[_msg.dstChainId][_msg.token];
        if (_maxTransferSize > 0) {
            require(
                transferInfo.size + _amount < _maxTransferSize,
                Rebalancer_TransferSizeExcedeed()
            );
        }

        // retrieve amounts (make sure to check min and max for that bridge)
        require(allowedList[_market], Rebalancer_MarketNotValid());
        IRebalanceMarket(_market).extractForRebalancing(_amount);

        // log
        unchecked {
            ++nonce;
        }
        logs[_msg.dstChainId][nonce] = _msg;

        // approve and trigger send
        SafeApprove.safeApprove(_msg.token, _bridge, _amount);
        IBridge(_bridge).sendMsg{value: msg.value}(
            _amount, _market, _msg.dstChainId, _msg.token, _msg.message, _msg.bridgeData
        );

        emit MsgSent(_bridge, _msg.dstChainId, _msg.token, _msg.message, _msg.bridgeData);
    }
}
