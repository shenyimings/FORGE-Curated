// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title INetwork
/// @author kexley, @capLabs
/// @notice Interface for Network contract
interface INetwork {
    /// @custom:storage-location erc7201:cap.storage.Network
    struct NetworkStorage {
        address middleware;
    }

    /// @notice Register middleware contract
    /// @param _middleware Middleware contract
    /// @param _middlewareService Middleware service address
    function registerMiddleware(address _middleware, address _middlewareService) external;

    /// @notice Register vault with Symbiotic
    /// @param _vault Vault address
    function registerVault(address _vault, address _agent) external;
}
