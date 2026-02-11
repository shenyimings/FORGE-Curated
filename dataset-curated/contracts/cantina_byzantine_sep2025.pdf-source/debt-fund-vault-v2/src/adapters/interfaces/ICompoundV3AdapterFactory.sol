// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity >=0.5.0;

interface ICompoundV3AdapterFactory {
    /* EVENTS */

    event CreateCompoundV3Adapter(
        address indexed parentVault, address indexed comet, address cometRewards, address indexed compoundV3Adapter
    );

    /* FUNCTIONS */

    function compoundV3Adapter(address parentVault, address comet) external view returns (address);
    function isCompoundV3Adapter(address account) external view returns (bool);
    function createCompoundV3Adapter(address parentVault, address comet, address cometRewards)
        external
        returns (address compoundV3Adapter);
}
