// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {VaultV2} from "@vault-v2/src/VaultV2.sol";

library VaultV2Lib {
    /// @notice Adds an allocator to a VaultV2 instance, assume 0-day timelocks
    function addAllocatorInstant(VaultV2 vault, address allocator) internal {
        bytes memory encoding = abi.encodeWithSelector(vault.setIsAllocator.selector, address(allocator), true);
        vault.submit(encoding);
        vault.setIsAllocator(address(allocator), true);
    }

    /// @notice Removes an allocator to a VaultV2 instance, assume 0-day timelocks
    function removeAllocatorInstant(VaultV2 vault, address allocator) internal {
        bytes memory encoding = abi.encodeWithSelector(vault.setIsAllocator.selector, address(allocator), false);
        vault.submit(encoding);
        vault.setIsAllocator(address(allocator), false);
    }

    /// @notice Adds collateral to a VaultV2 instance, assume 0-day timelocks
    function addCollateralInstant(VaultV2 vault, address adapter, bytes memory data, uint256 absolute, uint256 relative) internal {
        bytes memory encoding;
        // Accept the adapter
        if (!vault.isAdapter(address(adapter))) {
            encoding = abi.encodeWithSelector(vault.addAdapter.selector, address(adapter));
            vault.submit(encoding);
            vault.addAdapter(address(adapter));
        }

        // Absolute limit
        encoding = abi.encodeWithSelector(
            vault.increaseAbsoluteCap.selector,
            data,
            absolute // 100,000 USDC
        );
        vault.submit(encoding);
        vault.increaseAbsoluteCap(data, absolute);

        // Relative limit
        encoding = abi.encodeWithSelector(
            vault.increaseRelativeCap.selector,
            data,
            relative // 100%
        );
        vault.submit(encoding);
        vault.increaseRelativeCap(data, relative);
    }

    /// @notice Adds collateral to a VaultV2 instance, assume 0-day timelocks
    function setForceDeallocatePenaltyInstant(VaultV2 vault, address adapter, uint256 penalty) internal {
        bytes memory encoding = abi.encodeWithSelector(vault.setForceDeallocatePenalty.selector, address(adapter), penalty);
        vault.submit(encoding);
        vault.setForceDeallocatePenalty(address(adapter), penalty);
    }
}
