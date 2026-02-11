// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { IBridgeCoordinator } from "../interfaces/IBridgeCoordinator.sol";
import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { Bytes32AddressLib } from "../utils/Bytes32AddressLib.sol";

abstract contract BaseBridgeCoordinator is
    AccessControlUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    IBridgeCoordinator
{
    /**
     * @notice The address of the Generic unit that this coordinator manages
     */
    address public genericUnit;

    /**
     * @notice Configuration for the local bridge adapter
     * @param outbound The local bridge adapter contract used for outbound messages
     * @param isAdapter Mapping of adapter addresses
     */
    struct LocalConfig {
        IBridgeAdapter outbound;
        mapping(address => bool) isAdapter;
    }

    /**
     * @notice Configuration for a remote bridge adapter on another chain
     * @param outbound The remote bridge adapter address (encoded as bytes32) used for outbound messages
     * @param isAdapter Mapping of remote adapter identifiers (encoded as bytes32)
     */
    struct RemoteConfig {
        bytes32 outbound;
        mapping(bytes32 => bool) isAdapter;
    }

    /**
     * @notice Encapsulates both local and remote configurations for a specific bridge type
     * @dev Maps chain IDs to their respective remote configurations
     * @param local The local bridge adapter configuration
     * @param remote Mapping of chain IDs to their remote bridge adapter configurations
     */
    struct BridgeTypeConfig {
        LocalConfig local;
        mapping(uint256 chainId => RemoteConfig) remote;
    }

    /**
     * @notice Mapping of bridge types to their respective configurations
     */
    mapping(uint16 bridgeType => BridgeTypeConfig) internal bridgeTypes;

    /**
     * @notice Mapping of message IDs to their failed execution message hashes
     * @dev Used to track messages that failed during inbound settlement for potential rollback
     */
    mapping(bytes32 messageId => bytes32 messageHash) public failedMessageExecutions;

    /**
     * @notice Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;

    /**
     * @notice Checks if a specific bridge type is supported for a destination chain
     * @dev Returns true only if both local and remote adapters are configured
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The destination chain ID to check support for
     * @return True if the bridge type is supported for the specified chain, false otherwise
     */
    function supportsBridgeTypeFor(uint16 bridgeType, uint256 chainId) public view returns (bool) {
        bool localAdapter = address(bridgeTypes[bridgeType].local.outbound) != address(0);
        bool remoteAdapter = bridgeTypes[bridgeType].remote[chainId].outbound != bytes32(0);
        return localAdapter && remoteAdapter;
    }

    /**
     * @notice Returns the outbound local bridge adapter for a specific bridge type
     * @param bridgeType The identifier for the bridge protocol
     * @return The local bridge adapter contract used for outbound messages
     */
    function outboundLocalBridgeAdapter(uint16 bridgeType) public view returns (IBridgeAdapter) {
        return bridgeTypes[bridgeType].local.outbound;
    }

    /**
     * @notice Checks if an address is a local bridge adapter
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address to check
     * @return True if a local adapter, false otherwise
     */
    function isLocalBridgeAdapter(uint16 bridgeType, address adapter) public view returns (bool) {
        return bridgeTypes[bridgeType].local.isAdapter[adapter];
    }

    /**
     * @notice Returns the outbound remote bridge adapter for a specific bridge type and chain
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @return The remote bridge adapter address (encoded as bytes32) used for outbound messages
     */
    function outboundRemoteBridgeAdapter(uint16 bridgeType, uint256 chainId) public view returns (bytes32) {
        return bridgeTypes[bridgeType].remote[chainId].outbound;
    }

    /**
     * @notice Checks if an address is a remote bridge adapter for a specific bridge type and chain
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The remote bridge adapter address (encoded as bytes32) to check
     * @return True if the adapter is a remote bridge adapter, false otherwise
     */
    function isRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        public
        view
        returns (bool)
    {
        return bridgeTypes[bridgeType].remote[chainId].isAdapter[adapter];
    }

    /**
     * @notice Encodes an EVM address to bytes32 for cross-chain compatibility
     * @param addr The EVM address to encode
     * @return The address encoded as bytes32
     */
    function encodeOmnichainAddress(address addr) public pure returns (bytes32) {
        return Bytes32AddressLib.toBytes32WithLowAddress(addr);
    }

    /**
     * @notice Decodes a bytes32 value back to an EVM address
     * @param oAddr The bytes32 encoded address
     * @return The decoded EVM address
     */
    function decodeOmnichainAddress(bytes32 oAddr) public pure returns (address) {
        return Bytes32AddressLib.toAddressFromLowBytes(oAddr);
    }

    /**
     * @notice Computes the hash for a failed message execution
     * @dev Used to track failed inbound message settlements. The hash is not used as a unique identifier. Rather,
     * it allows verification that a provided failed message data corresponds to the original message.
     * @param chainId The source chain ID where the bridge operation originated
     * @param messageData The encoded bridge message data
     * @return The computed hash of the failed message
     */
    function _failedMessageHash(uint256 chainId, bytes memory messageData) internal pure returns (bytes32) {
        // forge-lint: disable-next-line(asm-keccak256)
        return keccak256(abi.encode(chainId, messageData));
    }

    /**
     * @notice Dispatches a cross-chain message via the specified bridge adapter
     * @dev Internal function that routes the message to the appropriate bridge adapter
     * @param bridgeType The identifier for the bridge protocol to use
     * @param chainId The destination chain ID
     * @param messageData The encoded bridge message data to be sent
     * @param bridgeParams Protocol-specific parameters required by the bridge adapter
     * @return messageId Unique identifier for tracking the cross-chain message
     */
    function _dispatchMessage(
        uint16 bridgeType,
        uint256 chainId,
        bytes memory messageData,
        bytes calldata bridgeParams
    )
        internal
        virtual
        returns (bytes32 messageId);

    /**
     * @notice Restricts units when bridging out
     * @dev Virtual function that inheriting contracts can override to implement burn/lock logic
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param owner The address that owns the units to be restricted
     * @param amount The amount of units to restrict
     */
    function _restrictUnits(address whitelabel, address owner, uint256 amount) internal virtual;

    /**
     * @notice Releases units when bridging in
     * @dev Virtual function that inheriting contracts can override to implement mint/unlock logic
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param receiver The address that should receive the released units
     * @param amount The amount of units to release
     */
    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal virtual;
}
