// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IVaultAdapter } from "../interfaces/IVaultAdapter.sol";

/// @title VaultAdapterStorageUtils
/// @author kexley, @capLabs
/// @notice Storage utilities for VaultAdapter contract
abstract contract VaultAdapterStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.VaultAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant VaultAdapterStorageLocation = 0x2b1d5d801322d1007f654ac87d8072a5f5ca4203517edc869ef2aa54addad600;

    /// @notice Get vault adapter storage
    /// @return $ Storage pointer
    function getVaultAdapterStorage() internal pure returns (IVaultAdapter.VaultAdapterStorage storage $) {
        assembly {
            $.slot := VaultAdapterStorageLocation
        }
    }
}
