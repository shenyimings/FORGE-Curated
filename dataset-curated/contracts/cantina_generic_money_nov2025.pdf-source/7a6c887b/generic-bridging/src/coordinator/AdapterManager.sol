// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseBridgeCoordinator, IBridgeAdapter } from "./BaseBridgeCoordinator.sol";

abstract contract AdapterManager is BaseBridgeCoordinator {
    /**
     * @notice The role that manages bridge configuration
     */
    bytes32 public constant ADAPTER_MANAGER_ROLE = keccak256("ADAPTER_MANAGER_ROLE");

    /**
     * @notice Emitted when a local bridge adapter's status is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address
     * @param isAdapter The new status of the adapter
     */
    event LocalBridgeAdapterUpdated(uint16 indexed bridgeType, address indexed adapter, bool isAdapter);
    /**
     * @notice Emitted when a remote bridge adapter's status is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The remote bridge adapter address (encoded as bytes32)
     * @param isAdapter The new status of the adapter
     */
    event RemoteBridgeAdapterUpdated(
        uint16 indexed bridgeType, uint256 indexed chainId, bytes32 indexed adapter, bool isAdapter
    );
    /**
     * @notice Emitted when the outbound local bridge adapter is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The new local bridge adapter address
     */
    event LocalOutboundBridgeAdapterUpdated(uint16 indexed bridgeType, address indexed adapter);
    /**
     * @notice Emitted when the outbound remote bridge adapter is updated
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The remote chain ID
     * @param adapter The new remote bridge adapter address (encoded as bytes32)
     */
    event RemoteOutboundBridgeAdapterUpdated(
        uint16 indexed bridgeType, uint256 indexed chainId, bytes32 indexed adapter
    );

    /**
     * @notice Thrown when bridge adapter's coordinator doesn't match this contract
     */
    error CoordinatorMismatch();
    /**
     * @notice Thrown when bridge adapter's type doesn't match the expected type
     */
    error BridgeTypeMismatch();
    /**
     * @notice Thrown when attempting to remove the outbound adapter from the adapter list
     */
    error IsOutboundAdapter();
    /**
     * @notice Thrown when the new outbound adapter is not in the adapter list
     */
    error IsNotAdapter();

    /**
     * @notice Sets a local bridge adapter for a specific bridge type
     * @dev Only callable by ADAPTER_MANAGER_ROLE. Validates adapter configuration if non-zero address provided.
     * Cannot remove the current outbound adapter.
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The local bridge adapter address
     * @param isAdapter Whether to add or remove the adapter from the adapter list
     */
    function setIsLocalBridgeAdapter(
        uint16 bridgeType,
        IBridgeAdapter adapter,
        bool isAdapter
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        LocalConfig storage config = bridgeTypes[bridgeType].local;
        if (isAdapter) {
            require(adapter.bridgeCoordinator() == address(this), CoordinatorMismatch());
            require(adapter.bridgeType() == bridgeType, BridgeTypeMismatch());
        } else {
            require(address(config.outbound) != address(adapter), IsOutboundAdapter());
        }
        config.isAdapter[address(adapter)] = isAdapter;
        emit LocalBridgeAdapterUpdated(bridgeType, address(adapter), isAdapter);
    }

    /**
     * @notice Sets a remote bridge adapter for a specific bridge type and chain
     * @dev Only callable by ADAPTER_MANAGER_ROLE. Cannot remove the current outbound adapter.
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The destination chain ID
     * @param adapter The remote bridge adapter address (encoded as bytes32)
     * @param isAdapter Whether to add or remove the adapter from the adapter list
     */
    function setIsRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter,
        bool isAdapter
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        RemoteConfig storage config = bridgeTypes[bridgeType].remote[chainId];
        if (!isAdapter) {
            require(config.outbound != adapter, IsOutboundAdapter());
        }
        config.isAdapter[adapter] = isAdapter;
        emit RemoteBridgeAdapterUpdated(bridgeType, chainId, adapter, isAdapter);
    }

    /**
     * @notice Sets an existing adapter as the outbound local bridge adapter for a specific bridge type
     * @dev Only callable by ADAPTER_MANAGER_ROLE.
     * @param bridgeType The identifier for the bridge protocol
     * @param adapter The new outbound local bridge adapter contract
     */
    function setOutboundLocalBridgeAdapter(
        uint16 bridgeType,
        IBridgeAdapter adapter
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        LocalConfig storage config = bridgeTypes[bridgeType].local;
        if (address(adapter) != address(0)) {
            require(config.isAdapter[address(adapter)], IsNotAdapter());
        }
        config.outbound = adapter;
        emit LocalOutboundBridgeAdapterUpdated(bridgeType, address(adapter));
    }

    /**
     * @notice Sets an existing adapter as the outbound remote bridge adapter for a specific bridge type and chain
     * @dev Only callable by ADAPTER_MANAGER_ROLE.
     * @param bridgeType The identifier for the bridge protocol
     * @param chainId The destination chain ID
     * @param adapter The new outbound remote bridge adapter address (encoded as bytes32)
     */
    function setOutboundRemoteBridgeAdapter(
        uint16 bridgeType,
        uint256 chainId,
        bytes32 adapter
    )
        external
        onlyRole(ADAPTER_MANAGER_ROLE)
    {
        RemoteConfig storage config = bridgeTypes[bridgeType].remote[chainId];
        if (adapter != bytes32(0)) {
            require(config.isAdapter[adapter], IsNotAdapter());
        }
        config.outbound = adapter;
        emit RemoteOutboundBridgeAdapterUpdated(bridgeType, chainId, adapter);
    }
}
