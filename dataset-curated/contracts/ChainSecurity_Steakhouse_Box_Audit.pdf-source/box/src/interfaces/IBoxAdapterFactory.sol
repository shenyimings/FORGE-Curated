// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association, Steakhouse Financial
pragma solidity >=0.8.0;

import {IBox} from "./IBox.sol";
import {IBoxAdapter} from "./IBoxAdapter.sol";

/// @notice Factory interface for BoxAdapter to link a Morpho Vault V2 and a Box
interface IBoxAdapterFactory {
    /* EVENTS */

    event CreateBoxAdapter(address indexed parentVault, address indexed box, IBoxAdapter indexed boxAdapter);

    /* FUNCTIONS */

    function boxAdapter(address parentVault, IBox box) external view returns (IBoxAdapter);
    function isBoxAdapter(address account) external view returns (bool);
    function createBoxAdapter(address parentVault, IBox box) external returns (IBoxAdapter boxAdapter);
}
