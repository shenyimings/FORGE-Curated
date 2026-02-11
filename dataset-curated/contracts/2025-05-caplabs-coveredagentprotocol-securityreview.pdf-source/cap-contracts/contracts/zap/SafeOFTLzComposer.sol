// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SafeOFTLzComposer
/// @author @capLabs
/// @notice LayerZero composer that sends back the OFT asset to the recipient if the handler fails.
abstract contract SafeOFTLzComposer is ILayerZeroComposer {
    using SafeERC20 for IERC20;

    uint256 public immutable fallbackGas = 40000;
    address public immutable oApp;
    address public immutable endpoint;

    error SafeOFTLzComposer_InvalidOApp();
    error SafeOFTLzComposer_InvalidEndpoint();
    error SafeOFTLzComposer_Unauthorized();

    constructor(address _oApp, address _endpoint) {
        oApp = _oApp;
        endpoint = _endpoint;
    }

    function lzCompose(
        address _oApp,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable override {
        // Perform checks to make sure composed message comes from correct OApp.
        if (_oApp != oApp) revert SafeOFTLzComposer_InvalidOApp();
        if (msg.sender != endpoint) revert SafeOFTLzComposer_InvalidEndpoint();

        // execute the handler and send back the oft asset to the recipient if the handler fails
        // 35000 is the gas limit for the fallback handler in case of a revert
        try SafeOFTLzComposer(address(this)).safeLzCompose{ gas: gasleft() - fallbackGas }(
            _oApp, _guid, _message, _executor, _extraData
        ) { } catch (bytes memory) {
            address fallbackRecipient = OFTComposeMsgCodec.bytes32ToAddress(OFTComposeMsgCodec.composeFrom(_message));
            address token = IOFT(oApp).token();
            uint256 amount = OFTComposeMsgCodec.amountLD(_message);
            if (amount > 0) {
                IERC20(token).safeTransfer(fallbackRecipient, amount);
            }
        }
    }

    /// @notice function called by lzCompose.
    /// @dev Is external to allow try/catch in lzCompose.
    function safeLzCompose(
        address _oApp,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external {
        if (msg.sender != address(this)) revert SafeOFTLzComposer_Unauthorized();
        _lzCompose(_oApp, _guid, _message, _executor, _extraData);
    }

    /// @notice function to be implemented by the child contract
    /// @dev This function can fail. If it does, the OFT asset will be sent back to the recipient.
    function _lzCompose(
        address _oApp,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal virtual;
}
