// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

struct SymbioticNetworkAdapterImplementationsConfig {
    address network;
    address networkMiddleware;
}

struct SymbioticNetworkAdapterConfig {
    address network;
    address networkMiddleware;
    uint256 feeAllowed;
}

struct SymbioticNetworkRewardsConfig {
    address stakerRewarder;
}

struct SymbioticNetworkAdapterParams {
    uint48 vaultEpochDuration;
    uint256 feeAllowed;
}

struct SymbioticUsersConfig {
    address vault_admin;
}

struct SymbioticVaultParams {
    address vault_admin;
    address collateral;
    uint48 vaultEpochDuration;
    uint48 burnerRouterDelay;
}

struct SymbioticVaultConfig {
    address vault;
    address collateral;
    address burnerRouter;
    address globalReceiver;
    address delegator;
    address slasher;
    uint48 vaultEpochDuration;
}
