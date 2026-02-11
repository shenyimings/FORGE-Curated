// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {MorphoVaultV1Adapter} from "@vault-v2/src/adapters/MorphoVaultV1Adapter.sol";

library MorphoVaultV1AdapterLib {
    /// @notice Returns the data to be used in the VaultV2 for the MetaMorpho adapter
    function data(MorphoVaultV1Adapter adapter) internal pure returns (bytes memory) {
        return abi.encode("this", adapter);
    }

    /// @notice Returns the id to be used in the VaultV2 for the MetaMorpho adapter
    function id(MorphoVaultV1Adapter adapter) internal pure returns (bytes32) {
        return keccak256(abi.encode("this", adapter));
    }
}
