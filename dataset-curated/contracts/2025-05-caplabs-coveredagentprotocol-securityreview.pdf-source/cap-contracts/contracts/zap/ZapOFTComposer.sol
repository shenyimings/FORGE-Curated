// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import { IZapRouter } from "../interfaces/IZapRouter.sol";

import { IZapOFTComposer } from "../interfaces/IZapOFTComposer.sol";
import { SafeOFTLzComposer } from "./SafeOFTLzComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ZapOFTComposer
/// @author @capLabs
/// @notice Compose an OFT with Zap capabilities
/// @dev This contract is used to compose an OFT message with Zap capabilities.
///      It handles ERC20 approvals, zap execution, and refunds the remaining tokens to the zap recipient.
///      Expects the funds to be sent to the ZapOFTComposer contract before the message is composed.
contract ZapOFTComposer is SafeOFTLzComposer {
    using SafeERC20 for IERC20;

    /// @notice Store ZapRouter addresses.
    address public immutable zapRouter;
    address public immutable zapTokenManager;

    /// @notice Constructs the contract.
    /// @param _endpoint The address of the LayerZero endpoint.
    /// @param _oApp The address of the OApp that is sending the composed message.
    /// @param _zapRouter The address of the ZapRouter to use for Zap capabilities.
    /// @param _zapTokenManager The address of the ZapTokenManager to use for token permissions.
    constructor(address _endpoint, address _oApp, address _zapRouter, address _zapTokenManager)
        SafeOFTLzComposer(_oApp, _endpoint)
    {
        zapRouter = _zapRouter;
        zapTokenManager = _zapTokenManager;
    }

    /// @notice Handles incoming composed messages from LayerZero OFTs and executes the zap order it represents.
    function _lzCompose(address, /*_oApp*/ bytes32, /*_guid*/ bytes calldata _message, address, bytes calldata)
        internal
        override
    {
        // Decode the payload to get the message
        bytes memory payload = OFTComposeMsgCodec.composeMsg(_message);
        IZapOFTComposer.ZapMessage memory zapMessage = abi.decode(payload, (IZapOFTComposer.ZapMessage));

        // approve all inputs to the zapTokenManager
        IZapRouter.Input[] memory inputs = zapMessage.order.inputs;
        uint256 inputLength = inputs.length;
        for (uint256 i = 0; i < inputLength; i++) {
            IZapRouter.Input memory input = inputs[i];
            if (input.amount > 0) {
                IERC20(input.token).forceApprove(zapTokenManager, input.amount);
            }
        }

        // execute the zap order
        IZapRouter(zapRouter).executeOrder(zapMessage.order, zapMessage.route);
    }
}
