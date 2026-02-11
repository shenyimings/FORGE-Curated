// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity 0.8.28;

import {ERC4626MerklAdapter} from "./ERC4626MerklAdapter.sol";
import {IERC4626MerklAdapterFactory} from "./interfaces/IERC4626MerklAdapterFactory.sol";

contract ERC4626MerklAdapterFactory is IERC4626MerklAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address erc4626Vault => address)) public erc4626MerklAdapter;
    mapping(address account => bool) public isERC4626MerklAdapter;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed ERC4626MerklAdapter.
    function createERC4626MerklAdapter(address parentVault, address erc4626Vault) external returns (address) {
        address _erc4626Adapter = address(new ERC4626MerklAdapter{salt: bytes32(0)}(parentVault, erc4626Vault));
        erc4626MerklAdapter[parentVault][erc4626Vault] = _erc4626Adapter;
        isERC4626MerklAdapter[_erc4626Adapter] = true;
        emit CreateERC4626MerklAdapter(parentVault, erc4626Vault, _erc4626Adapter);
        return _erc4626Adapter;
    }
}
