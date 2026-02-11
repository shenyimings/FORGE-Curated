// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @dev Parameters for cross-chain governance transaction
 * @param dstEid The destination endpoint ID
 * @param dstTarget The target contract address on the destination chain (as bytes32)
 * @param dstCallData The calldata to execute on the target contract
 * @param extraOptions Additional LayerZero options for the message
 */
struct TxParams {
    uint32 dstEid;
    bytes32 dstTarget;
    bytes dstCallData;
    bytes extraOptions;
}

/**
 * @title IGovernanceOAppSender
 * @dev Interface for the governance sender contract that handles outbound cross-chain governance calls
 * @notice This contract manages permissions and sends governance transactions to remote chains
 */
interface IGovernanceOAppSender {
    /**
     * @dev Thrown when trying to set the same canCallTarget value that's already set
     */
    error CanCallTargetIdempotent();

    /**
     * @dev Thrown when a sender attempts to call a target they don't have permission for
     */
    error CannotCallTarget();

    /**
     * @dev Emitted when a governance call is successfully sent to a remote chain
     * @param guid The unique identifier for the LayerZero message
     */
    event GovernanceCallSent(bytes32 indexed guid);

    /**
     * @dev Emitted when canCallTarget permission is updated
     * @param sender The address whose permission is being updated
     * @param dstEid The destination endpoint ID
     * @param dstTarget The target contract address (as bytes32)
     * @param canCall Whether the sender can call the target
     */
    event CanCallTargetSet(address indexed sender, uint32 indexed dstEid, bytes32 indexed dstTarget, bool canCall);

    /**
     * @dev The message type identifier for sending transactions
     * @return The message type constant (1)
     */
    function SEND_TX() external view returns (uint16);

    /**
     * @dev Check if a sender can call a specific target on a destination chain
     * @param _srcSender The address of the sender
     * @param _dstEid The destination endpoint ID
     * @param _dstTarget The target contract address (as bytes32)
     * @return canCall Whether the sender has permission to call the target
     */
    function canCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget) external view returns (bool canCall);

    /**
     * @dev Set permission for a sender to call a specific target on a destination chain
     * @param _srcSender The address of the sender
     * @param _dstEid The destination endpoint ID
     * @param _dstTarget The target contract address (as bytes32)
     * @param _canCall Whether to grant or revoke permission
     * @notice Only callable by the contract owner
     */
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;

    /**
     * @dev Quote the fee for sending a governance transaction
     * @param _params The transaction parameters
     * @param _payInLzToken Whether to pay the fee in LayerZero token
     * @return fee The messaging fee required for the transaction
     */
    function quoteTx(TxParams calldata _params, bool _payInLzToken) external view returns (MessagingFee memory fee);

    /**
     * @dev Send a governance transaction to a remote chain
     * @param _params The transaction parameters
     * @param _fee The messaging fee to pay
     * @param _refundAddress The address to receive any excess fee refund
     * @return msgReceipt The receipt containing the message GUID and other details
     * @notice Requires the caller to have permission via canCallTarget mapping
     */
    function sendTx(
        TxParams calldata _params,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt);
}
