// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity >=0.5.0;

interface IERC4626MerklAdapterFactory {
    /* EVENTS */

    event CreateERC4626MerklAdapter(
        address indexed parentVault, address indexed erc4626Vault, address indexed erc4626MerklAdapter
    );

    /* FUNCTIONS */

    function erc4626MerklAdapter(address parentVault, address erc4626Vault) external view returns (address);
    function isERC4626MerklAdapter(address account) external view returns (bool);
    function createERC4626MerklAdapter(address parentVault, address erc4626Vault)
        external
        returns (address erc4626Adapter);
}
