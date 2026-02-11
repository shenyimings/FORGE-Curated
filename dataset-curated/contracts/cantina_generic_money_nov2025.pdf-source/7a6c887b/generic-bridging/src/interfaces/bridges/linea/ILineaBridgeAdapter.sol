// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title ILineaBridgeAdapter
 * @notice Standard interface Linea bridge adapter
 */
interface ILineaBridgeAdapter {
    /**
     * @notice Receives a call from the message bridge to mint/redeem the units
     * @dev This function is the one to call for intrabridge messaging
     * @param message Encoded payload delivered by the transport, to be forwarded to the coordinator.
     * @param messageId Encoded message id given by the emitting chain (originChainId, messageServiceAddress, nonce)
     */
    function settleInboundBridge(bytes calldata message, bytes32 messageId) external;
}
