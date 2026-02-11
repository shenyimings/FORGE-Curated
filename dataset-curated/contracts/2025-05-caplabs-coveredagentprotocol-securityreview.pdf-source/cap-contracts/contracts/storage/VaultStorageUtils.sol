// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IVault } from "../interfaces/IVault.sol";

/// @title VaultStorageUtils
/// @author kexley, @capLabs
/// @notice Storage utilities for Vault contract
abstract contract VaultStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.Vault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant VaultStorageLocation = 0xe912a1b0cc7579bc5827e495c2ce52587bc3871751e3281fc5599b38c3bfc400;

    /// @notice Get vault storage
    /// @return $ Storage pointer
    function getVaultStorage() internal pure returns (IVault.VaultStorage storage $) {
        assembly {
            $.slot := VaultStorageLocation
        }
    }
}
