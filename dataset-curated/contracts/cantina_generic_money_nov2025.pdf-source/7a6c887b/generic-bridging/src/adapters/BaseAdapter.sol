// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { IBridgeCoordinator } from "../interfaces/IBridgeCoordinator.sol";

/**
 * @title BaseAdapter
 * @notice Abstract base contract for bridge adapters that provides common functionality
 * @dev Implements standard adapter properties and coordinator reference. Inheriting contracts
 * must implement the bridge and estimateBridgeFee functions for specific bridge protocols.
 */
abstract contract BaseAdapter is IBridgeAdapter, Ownable2Step {
    /**
     * @notice Thrown when an operation receives the zero address where a contract is required.
     */
    error InvalidZeroAddress();
    /**
     * @notice Thrown when a non-authorised caller attempts to invoke restricted functionality.
     */
    error UnauthorizedCaller();

    /**
     * @notice The bridge coordinator contract that this adapter is connected to
     */
    IBridgeCoordinator public immutable coordinator;

    /**
     * @notice Counter for the amount of bridging transactions done by the adapter
     */
    uint32 public nonce;

    /**
     * @notice Initializes the base adapter with bridge type and coordinator
     * @param _coordinator The bridge coordinator contract address
     */
    constructor(IBridgeCoordinator _coordinator, address owner) Ownable(owner) {
        coordinator = _coordinator;
    }

    /**
     * @notice Returns the address of the bridge coordinator this adapter is connected to
     * @return The address of the bridge coordinator contract
     */
    function bridgeCoordinator() external view override returns (address) {
        return address(coordinator);
    }

    /**
     * @notice Returns the bridge type identifier for this adapter implementation
     * @return The uint16 bridge type identifier
     */
    function bridgeType() public view virtual returns (uint16);

    /**
     * @notice Returns the messageId for the bridging and receiving of the units
     * @param chainId The destination chain ID for the bridge operation
     * @return The bytes32 encoded messageId of the bridge transaction
     */
    function getMessageId(uint256 chainId) public view returns (bytes32) {
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encodePacked(chainId, bridgeType(), block.timestamp, nonce));
    }

    /// @inheritdoc IBridgeAdapter
    function bridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (bytes32 messageId)
    {
        require(msg.sender == address(coordinator), UnauthorizedCaller());

        messageId = getMessageId(chainId);
        unchecked {
            ++nonce;
        }

        _dispatchBridge(chainId, remoteAdapter, message, refundAddress, bridgeParams, messageId);
    }

    /**
     * @notice Dispatches an outbound message through the underlying bridge implementation.
     * @param chainId Destination chain identifier recognised by the adapter implementation.
     * @param remoteAdapter Encoded address or identifier of the remote adapter endpoint.
     * @param message Payload forwarded to the remote coordinator for settlement.
     * @param refundAddress Address to refund any excess fees or failed transactions.
     * @param bridgeParams Adapter-specific parameters used to quote and configure the bridge call.
     * @param messageId The internal only message id for the transaction
     */
    function _dispatchBridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId
    )
        internal
        virtual;
}
