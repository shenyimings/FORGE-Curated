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

interface IRebalanceMarket {
    function extractForRebalancing(uint256 amount) external;
}

interface IRebalancer {
    // ----------- STORAGE ------------
    struct Msg {
        uint32 dstChainId;
        address token;
        bytes message;
        bytes bridgeData;
    }
    // ----------- EVENTS ------------

    event BridgeWhitelistedStatusUpdated(address indexed bridge, bool status);
    event MsgSent(
        address indexed bridge, uint32 indexed dstChainId, address indexed token, bytes message, bytes bridgeData
    );

    event EthSaved(uint256 amount);
    event MaxTransferSizeUpdated(uint32 indexed dstChainId, address indexed token, uint256 newLimit);
    event MinTransferSizeUpdated(uint32 indexed dstChainId, address indexed token, uint256 newLimit);
    event DestinationWhitelistedStatusUpdated(uint32 indexed dstChainId, bool status);
    event AllowedListUpdated(address[] list, bool status);

    // ----------- ERRORS ------------
    error Rebalancer_NotAuthorized();
    error Rebalancer_MarketNotValid();
    error Rebalancer_RequestNotValid();
    error Rebalancer_AddressNotValid();
    error Rebalancer_BridgeNotWhitelisted();
    error Rebalancer_TransferSizeExcedeed();
    error Rebalancer_TransferSizeMinNotMet();
    error Rebalancer_DestinationNotWhitelisted();

    // ----------- VIEW METHODS ------------
    /**
     * @notice returns current nonce
     */
    function nonce() external view returns (uint256);

    /**
     * @notice returns if a bridge implementation is whitelisted
     */
    function isBridgeWhitelisted(address bridge) external view returns (bool);

    /**
     * @notice returns if a destination is whitelisted
     */
    function isDestinationWhitelisted(uint32 dstId) external view returns (bool);

    // ----------- EXTERNAL METHODS ------------
    /**
     * @notice sends a bridge message
     * @param bridge the whitelisted bridge address
     * @param _market the market to rebalance from address
     * @param _amount the amount to rebalance
     * @param msg the message data
     */
    function sendMsg(address bridge, address _market, uint256 _amount, Msg calldata msg) external payable;
}
