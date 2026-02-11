// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

/// @notice Credit account filters
/// @param  owner If set, match credit accounts owned by given address
/// @param  includeZeroDebt If `true`, also match accounts with zero debt
/// @param  minHealthFactor If set, only return accounts with health factor above this value
/// @param  maxHealthFactor If set, only return accounts with health factor below this value
/// @param  reverting If `true`, only match accounts with reverting collateral calculation
struct CreditAccountFilter {
    address owner;
    bool includeZeroDebt;
    uint256 minHealthFactor;
    uint256 maxHealthFactor;
    bool reverting;
}

// NOTE: since anyone can create a market configurator permissionlessly (that's kinda the whole point),
// the number of markets and credit suites can be arbitrarily large, so it's better to always specify
// non-malicious configurators when using the two following filters in order not to get DoS-ed.

/// @notice Credit manager filters
/// @param  configurators If set, match credit managers by given market configurators
/// @param  creditManagers If set, only include credit managers if they are in this list
/// @param  pools If set, match credit managers connected to given pools
/// @param  underlying If set, match credit managers with given underlying
struct CreditManagerFilter {
    address[] configurators;
    address[] creditManagers;
    address[] pools;
    address underlying;
}

/// @notice Market filters
/// @param  configurators If set, match markets by given market configurators
/// @param  pools If set, only include markets if they are in this list
/// @param  underlying If set, match markets with given underlying
struct MarketFilter {
    address[] configurators;
    address[] pools;
    address underlying;
}
