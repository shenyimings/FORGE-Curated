// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IOAppMsgInspector} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IOFT, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title OVaultMsgInspector
 * @notice Validates OFT messages before sending to prevent invalid cross-chain transactions
 * @dev Implements IOAppMsgInspector to validate message contents on the source chain
 *      before LayerZero sends them, avoiding costly refund processes.
 *
 * Key validations:
 * 1. Receiver addresses must not be zero (prevents minting to address(0))
 * 2. Destination addresses in SendParams must not be zero (for cross-chain sends)
 * 3. Compose messages must have valid structure when present
 *
 * This inspector is designed to work with OVaultComposerMulti and validates:
 * - ACTION_DEPOSIT_ASSET (1): Validates targetAsset deposits
 * - ACTION_REDEEM_SHARES (2): Validates share redemptions
 */
contract OVaultMsgInspector is IOAppMsgInspector {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    // Compose message action types (must match OVaultComposerMulti)
    uint8 constant ACTION_DEPOSIT_ASSET = 1;
    uint8 constant ACTION_REDEEM_SHARES = 2;

    // Custom errors for clearer failure reasons
    error InvalidReceiver();
    error InvalidDestination();
    error InvalidComposeMsg();
    error InvalidAction(uint8 action);
    error InvalidTargetAsset();

    /**
     * @notice Inspects the OFT message and options before sending
     * @param _message The encoded OFT message (sendTo, amountSD, composeMsg)
     * @param _options The LayerZero options (unused but required by interface)
     * @return valid Always returns true if validation passes, reverts otherwise
     *
     * @dev Message structure (from OFTMsgCodec):
     *      - bytes32 sendTo (32 bytes)
     *      - uint64 amountSD (8 bytes)
     *      - bytes32 composeFrom (32 bytes) - only if composed
     *      - bytes composeMsg (variable) - only if composed
     *
     * @dev ComposeMsg structure for each action:
     *      ACTION_DEPOSIT_ASSET:
     *        (address targetAsset, bytes32 receiver, SendParam sendParam, uint256 minMsgValue, bytes32 unused)
     *
     *      ACTION_REDEEM_SHARES:
     *        (address receiver, SendParam sendParam, uint256 minMsgValue, uint256 minAssets)
     *
     */
    function inspect(bytes calldata _message, bytes calldata _options) external pure override returns (bool) {
        // Validate the primary recipient address (always present)
        bytes32 sendTo = _message.sendTo();
        if (sendTo == bytes32(0)) revert InvalidReceiver();

        // If message is composed, validate compose payload
        if (_message.isComposed()) {
            _validateComposeMsg(_message.composeMsg());
        }

        return true;
    }

    /**
     * @notice Validates the compose message payload
     * @param _fullComposeMsg The full compose message including composeFrom and actual payload
     * @dev The full compose message starts with bytes32 composeFrom, then the actual compose data
     */
    function _validateComposeMsg(bytes memory _fullComposeMsg) internal pure {
        // Skip the first 32 bytes (composeFrom) to get to the actual compose message
        if (_fullComposeMsg.length <= 32) revert InvalidComposeMsg();

        bytes memory actualComposeMsg = _sliceBytes(_fullComposeMsg, 32, _fullComposeMsg.length - 32);

        // Decode action type (first byte of the actual compose message)
        (uint8 action, bytes memory params) = abi.decode(actualComposeMsg, (uint8, bytes));

        // Validate based on action type
        if (action == ACTION_DEPOSIT_ASSET) {
            _validateDepositAsset(params);
        } else if (action == ACTION_REDEEM_SHARES) {
            _validateRedeemShares(params);
        } else {
            revert InvalidAction(action);
        }
    }

    /**
     * @notice Validates deposit asset compose message parameters
     * @param _params Encoded parameters: (address targetAsset, bytes32 receiver, SendParam sendParam, uint256 minMsgValue, bytes32 unused)
     */
    function _validateDepositAsset(bytes memory _params) internal pure {
        (address targetAsset, bytes32 receiver, SendParam memory sendParam,,) =
            abi.decode(_params, (address, bytes32, SendParam, uint256, bytes32));

        // Validate target asset is not zero
        if (targetAsset == address(0)) revert InvalidTargetAsset();

        // Validate receiver is not zero
        if (receiver == bytes32(0)) revert InvalidReceiver();

        // If cross-chain send is requested, validate destination
        if (sendParam.dstEid != 0 && sendParam.to == bytes32(0)) {
            revert InvalidDestination();
        }
    }

    /**
     * @notice Validates redeem shares compose message parameters
     * @param _params Encoded parameters: (address receiver, SendParam sendParam, uint256 minMsgValue, uint256 minAssets)
     */
    function _validateRedeemShares(bytes memory _params) internal pure {
        (address receiver, SendParam memory sendParam,,) =
            abi.decode(_params, (address, SendParam, uint256, uint256));

        // Validate receiver is not zero
        if (receiver == address(0)) revert InvalidReceiver();

        // If cross-chain send is requested, validate destination
        if (sendParam.dstEid != 0 && sendParam.to == bytes32(0)) {
            revert InvalidDestination();
        }
    }

    /**
     * @notice Helper function to slice bytes
     * @param _data The bytes to slice
     * @param _start The start index
     * @param _length The length to slice
     * @return The sliced bytes
     */
    function _sliceBytes(bytes memory _data, uint256 _start, uint256 _length)
        internal
        pure
        returns (bytes memory)
    {
        require(_start + _length <= _data.length, "Slice out of bounds");

        bytes memory result = new bytes(_length);
        for (uint256 i = 0; i < _length; i++) {
            result[i] = _data[_start + i];
        }
        return result;
    }
}
