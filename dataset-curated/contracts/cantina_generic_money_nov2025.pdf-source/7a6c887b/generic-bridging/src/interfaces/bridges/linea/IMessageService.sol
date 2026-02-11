// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IMessageService
 * @notice Minimal interface for Linea's canonical message service used by the bridge adapter.
 */
interface IMessageService {
    /**
     * @notice Claims a previously relayed message on the destination chain.
     * @param from Original sender on the source chain.
     * @param to Target contract on the destination chain to execute the payload.
     * @param fee Native fee charged by the message service for processing the claim.
     * @param value Value (if any) forwarded to the target contract along with the call.
     * @param feeRecipient Address receiving the settlement fee on the destination chain.
     * @param callData Encoded call data forwarded to the target contract.
     * @param nonce Unique identifier of the message being claimed.
     */
    function claimMessage(
        address from,
        address to,
        uint256 fee,
        uint256 value,
        address payable feeRecipient,
        bytes calldata callData,
        uint256 nonce
    )
        external;

    /**
     * @notice Sends a message for transporting from the current chain to the destination chain.
     * @dev Must be called with `msg.value == _fee + _value` if the payload forwards native ETH.
     * @param _to Destination address on the remote chain.
     * @param _fee Native fee charged on the origin chain.
     * @param _calldata Encoded payload executed by the destination message service.
     */
    function sendMessage(address _to, uint256 _fee, bytes calldata _calldata) external payable;

    /**
     * @notice Returns the address that initiated the current message.
     * @return The source address recorded by the message service.
     */
    function sender() external view returns (address);
}
