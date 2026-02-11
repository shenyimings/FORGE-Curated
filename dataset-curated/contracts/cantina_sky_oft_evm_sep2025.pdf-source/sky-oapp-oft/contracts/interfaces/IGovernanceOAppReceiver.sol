// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @dev Information about the origin of a cross-chain governance message
 * @param srcEid The source endpoint ID where the message originated
 * @param srcSender The address of the original sender on the source chain (as bytes32)
 */
struct MessageOrigin {
    uint32 srcEid;
    bytes32 srcSender;
}

/**
 * @title IGovernanceOAppReceiver
 * @dev Interface for the governance receiver contract that handles inbound cross-chain governance calls
 * @notice This contract receives and executes governance transactions from remote chains
 */
interface IGovernanceOAppReceiver {
    /**
     * @dev Thrown when a governance call execution fails on the target contract
     */
    error GovernanceCallFailed();

    /**
     * @dev Emitted when a governance call is successfully received and executed
     * @param guid The unique identifier for the LayerZero message
     */
    event GovernanceCallReceived(bytes32 indexed guid);

    /**
     * @dev Get the origin information of the current cross-chain governance message
     * @return The MessageOrigin struct containing source endpoint ID and sender address
     * @notice This function should be called by target contracts to validate the message origin
     * @notice Returns zero values when no message is being processed
     */
    function messageOrigin() external view returns (MessageOrigin memory);
}
