// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBeaconProxyFactory {
    /// @notice Error thrown when an invalid address is provided
    error InvalidAddress();

    /// @notice Emitted when a new BeaconProxy is created
    /// @param proxy The address of the new BeaconProxy
    /// @param data The data used to initialize the BeaconProxy
    /// @param baseSalt The base salt used for deterministic deployment
    event BeaconProxyCreated(address indexed proxy, bytes data, bytes32 baseSalt);

    /// @notice Computes the address of a BeaconProxy before deployment
    /// @param sender The address that will deploy the BeaconProxy using the factory
    /// @param data The initialization data passed to the BeaconProxy
    /// @param baseSalt The base salt used for deterministic deployment
    /// @return proxy The predicted address of the BeaconProxy
    function computeProxyAddress(address sender, bytes memory data, bytes32 baseSalt)
        external
        view
        returns (address proxy);

    /// @notice Returns the number of BeaconProxys deployed by the factory
    /// @return _numProxies The number of BeaconProxys deployed by the factory
    function numProxies() external view returns (uint256 _numProxies);

    /// @notice Creates a new beacon proxy
    /// @param data The initialization data passed to the proxy
    /// @param baseSalt The base salt used for deterministic deployment
    /// @return proxy The address of the new BeaconProxy
    function createProxy(bytes memory data, bytes32 baseSalt) external returns (address proxy);
}
