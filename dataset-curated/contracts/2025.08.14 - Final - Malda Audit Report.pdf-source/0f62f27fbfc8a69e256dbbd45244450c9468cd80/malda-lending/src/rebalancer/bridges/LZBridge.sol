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

// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MessagingReceipt} from "src/interfaces/external/layerzero/v2/ILayerZeroEndpointV2.sol";
import {ILayerZeroOFT, SendParam, MessagingFee} from "src/interfaces/external/layerzero/v2/ILayerZeroOFT.sol";

import {IBridge} from "src/interfaces/IBridge.sol";
import {ImTokenMinimal} from "src/interfaces/ImToken.sol";

import {BaseBridge} from "src/rebalancer/bridges/BaseBridge.sol";

contract LZBridge is BaseBridge, IBridge {
    using SafeERC20 for IERC20;

    // ----------- STORAGE ------------

    // ----------- EVENTS ------------
    event MsgSent(
        uint32 indexed dstChainId, address indexed market, uint256 amountLD, uint256 minAmountLD, bytes32 guid
    );

    error LZBridge_NotEnoughFees();
    error LZBridge_ChainNotRegistered();
    error LZBridge_DestinationMismatch();

    constructor(address _roles) BaseBridge(_roles) {}

    // ----------- VIEW ------------
    /**
     * @inheritdoc IBridge
     * @dev use `getOptionsData` for `_bridgeData`
     */
    function getFee(uint32 _dstChainId, bytes memory _message, bytes memory _composeMsg)
        external
        view
        returns (uint256)
    {
        require(_dstChainId > 0, LZBridge_ChainNotRegistered());

        (MessagingFee memory fees,) = _getFee(_dstChainId, _message, _composeMsg);
        return fees.nativeFee; // no option to pay in LZ token with this version
    }

    // ----------- EXTERNAL ------------
    /**
     * @inheritdoc IBridge
     */
    function sendMsg(
        uint256 _extractedAmount,
        address _market,
        uint32 _dstChainId,
        address _token,
        bytes memory _message,
        bytes memory _composeMsg
    ) external payable onlyRebalancer {
        require(_dstChainId > 0, LZBridge_ChainNotRegistered());

        // get market
        (address market,,,) = abi.decode(_message, (address, uint256, uint256, bytes));
        require(_market == market, LZBridge_DestinationMismatch());

        // compute fee and craft message
        (MessagingFee memory fees, SendParam memory sendParam) = _getFee(_dstChainId, _message, _composeMsg);
        if (msg.value < fees.nativeFee) revert LZBridge_NotEnoughFees();
        require(_extractedAmount == sendParam.amountLD, BaseBridge_AmountMismatch());

        // retrieve tokens from `Rebalancer`
        IERC20(_token).safeTransferFrom(msg.sender, address(this), sendParam.amountLD);

        // send OFT
        (MessagingReceipt memory msgReceipt,) = ILayerZeroOFT(_token).send{value: msg.value}(sendParam, fees, market); // refundAddress = market

        emit MsgSent(_dstChainId, market, sendParam.amountLD, sendParam.minAmountLD, msgReceipt.guid);
    }

    // ----------- PRIVATE ------------
    function _getFee(uint32 dstEid, bytes memory _message, bytes memory _composeMsg)
        private
        view
        returns (MessagingFee memory fees, SendParam memory lzSendParams)
    {
        (address market, uint256 amountLD, uint256 minAmountLD, bytes memory extraOptions) =
            abi.decode(_message, (address, uint256, uint256, bytes));
        lzSendParams = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(market))), // deployed with CREATE3
            amountLD: amountLD,
            minAmountLD: minAmountLD,
            extraOptions: extraOptions,
            composeMsg: _composeMsg,
            oftCmd: ""
        });
        address _underlying = ImTokenMinimal(market).underlying();

        fees = ILayerZeroOFT(_underlying).quoteSend(lzSendParams, false);
    }
}
