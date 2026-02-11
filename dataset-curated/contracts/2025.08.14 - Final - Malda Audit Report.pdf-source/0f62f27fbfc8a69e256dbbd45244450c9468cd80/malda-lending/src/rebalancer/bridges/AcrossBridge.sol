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
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {SafeApprove} from "src/libraries/SafeApprove.sol";

import {IBridge} from "src/interfaces/IBridge.sol";
import {ImTokenMinimal} from "src/interfaces/ImToken.sol";
import {IAcrossSpokePoolV3} from "src/interfaces/external/across/IAcrossSpokePoolV3.sol";

import {BaseBridge} from "src/rebalancer/bridges/BaseBridge.sol";

contract AccrossBridge is BaseBridge, IBridge, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------- STORAGE ------------
    address public immutable acrossSpokePool;
    uint256 public immutable maxSlippage;
    mapping(uint32 => mapping(address => bool)) public whitelistedRelayers;

    uint256 private constant SLIPPAGE_PRECISION = 1e5;

    struct DecodedMessage {
        uint256 inputAmount;
        uint256 outputAmount;
        address relayer;
        uint32 deadline;
        uint32 exclusivityDeadline;
    }

    // ----------- EVENTS ------------
    event Rebalanced(address indexed market, uint256 amount);
    event WhitelistedRelayerStatusUpdated(
        address indexed sender, uint32 indexed dstId, address indexed delegate, bool status
    );

    // ----------- ERRORS ------------
    error AcrossBridge_TokenMismatch();
    error AcrossBridge_NotAuthorized();
    error AcrossBridge_NotImplemented();
    error AcrossBridge_AddressNotValid();
    error AcrossBridge_SlippageNotValid();
    error AcrossBridge_RelayerNotValid();

    constructor(address _roles, address _spokePool) BaseBridge(_roles) {
        require(_spokePool != address(0), AcrossBridge_AddressNotValid());
        acrossSpokePool = _spokePool;
        maxSlippage = 1e4;
    }

    modifier onlySpokePool() {
        require(msg.sender == acrossSpokePool, AcrossBridge_NotAuthorized());
        _;
    }

    // ----------- OWNER ------------
    /**
     * @notice Whitelists a delegate address
     */
    function setWhitelistedRelayer(uint32 _dstId, address _relayer, bool status) external onlyBridgeConfigurator {
        whitelistedRelayers[_dstId][_relayer] = status;
        emit WhitelistedRelayerStatusUpdated(msg.sender, _dstId, _relayer, status);
    }

    // ----------- VIEW ------------
    /**
     * @inheritdoc IBridge
     */
    function getFee(uint32, bytes memory, bytes memory) external pure returns (uint256) {
        // need to use Across API
        revert AcrossBridge_NotImplemented();
    }

    /**
     * @notice returns if an address represents a whitelisted delegates
     */
    function isRelayerWhitelisted(uint32 dstChain, address relayer) external view returns (bool) {
        return whitelistedRelayers[dstChain][relayer];
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
        bytes memory
    ) external payable onlyRebalancer {
        // decode message & checks
        DecodedMessage memory msgData = _decodeMessage(_message);
        require(_extractedAmount == msgData.inputAmount, BaseBridge_AmountMismatch());
        require(whitelistedRelayers[_dstChainId][msgData.relayer], AcrossBridge_RelayerNotValid());

        // retrieve tokens from `Rebalancer`
        IERC20(_token).safeTransferFrom(msg.sender, address(this), msgData.inputAmount);

        if (msgData.inputAmount > msgData.outputAmount) {
            uint256 maxSlippageInputAmount = msgData.inputAmount * maxSlippage / SLIPPAGE_PRECISION;
            require(
                msgData.inputAmount - msgData.outputAmount <= maxSlippageInputAmount, AcrossBridge_SlippageNotValid()
            );
        }

        // approve and send with Across
        _depositV3Now(_message, _token, _dstChainId, _market);
    }

    /**
     * @notice handles AcrossV3 SpokePool message
     * @param tokenSent the token address received
     * @param amount the token amount
     * @param message the custom message sent from source
     */
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address, // relayer is unused
        bytes memory message
    ) external onlySpokePool nonReentrant {
        address market = abi.decode(message, (address));
        address _underlying = ImTokenMinimal(market).underlying();
        require(_underlying == tokenSent, AcrossBridge_TokenMismatch());
        if (amount > 0) {
            IERC20(tokenSent).safeTransfer(market, amount);
        }

        emit Rebalanced(market, amount);
    }

    // ----------- PRIVATE ------------
    function _decodeMessage(bytes memory _message) private pure returns (DecodedMessage memory) {
        (uint256 inputAmount, uint256 outputAmount, address relayer, uint32 deadline, uint32 exclusivityDeadline) =
            abi.decode(_message, (uint256, uint256, address, uint32, uint32));

        return DecodedMessage(inputAmount, outputAmount, relayer, deadline, exclusivityDeadline);
    }

    function _depositV3Now(bytes memory _message, address _token, uint32 _dstChainId, address _market) private {
        DecodedMessage memory msgData = _decodeMessage(_message);
        // approve and send with Across
        SafeApprove.safeApprove(_token, address(acrossSpokePool), msgData.inputAmount);
        IAcrossSpokePoolV3(acrossSpokePool).depositV3Now( // no need for `msg.value`; fee is taken from amount
            msg.sender, //depositor
            address(this), //recipient
            _token,
            address(0), //outputToken is automatically resolved to the same token on destination
            msgData.inputAmount,
            msgData.outputAmount, //outputAmount should be set as the inputAmount - relay fees; use Across API
            uint256(_dstChainId),
            msgData.relayer, //exclusiveRelayer
            msgData.deadline, //fillDeadline
            msgData.exclusivityDeadline, //can use Across API/suggested-fees or 0 to disable
            abi.encode(_market)
        );
    }
}
