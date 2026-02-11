// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

/// @title Transient storage
/// @notice Library for loading and storing data in transient storage.
library TransientStorage {
    using TransientSlot for *;

    // keccak256(abi.encode(uint256(keccak256("sBold.collateralInBold")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant COLLATERAL_IN_BOLD_STORAGE =
        0x93de9a8576a62ce59fcb637d8053d0e5fadcf7d26694489a7981d83007528a00;
    // keccak256(abi.encode(uint256(keccak256("sBold.collateralValue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant COLLATERAL_VALUE_STORAGE =
        0xb9119c9d507ab94e0f4429b4c7bbf0463ef7a3523c74e225b6641cfb04e67a00;
    // keccak256(abi.encode(uint256(keccak256("sBold.collateralInBoldFlag")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant COLLATERALS_FLAG_STORAGE =
        0x7f4a0d96299dae48c93382764b8799886298548aad0eae1e31f8351df5706900;

    /// @dev Stores the collateral values in transient storage.
    /// @param collValue The collateral in USD value to be stored.
    /// @param collInBold The collateral in $BOLD value to be stored.
    function storeCollValues(uint256 collValue, uint256 collInBold) internal {
        // Transient store for collateral in $BOLD flag
        COLLATERALS_FLAG_STORAGE.asBoolean().tstore(true);
        // Transient store for collateral in USD
        COLLATERAL_VALUE_STORAGE.asUint256().tstore(collValue);
        // Transient store for collateral in $BOLD
        COLLATERAL_IN_BOLD_STORAGE.asUint256().tstore(collInBold);
    }

    /// @dev Clears the collateral in $BOLD value from transient storage.
    function switchOffCollInBoldFlag() internal {
        COLLATERALS_FLAG_STORAGE.asBoolean().tstore(false);
    }

    /// @dev Loads the collaterals flag from transient storage.
    /// @return The boolean flag.
    function loadCollsFlag() internal view returns (bool) {
        return COLLATERALS_FLAG_STORAGE.asBoolean().tload();
    }

    /// @dev Loads the collateral in $BOLD value from transient storage.
    /// @return The value.
    function loadCollInBold() internal view returns (uint256) {
        return COLLATERAL_IN_BOLD_STORAGE.asUint256().tload();
    }

    /// @dev Loads the collateral in USD value from transient storage.
    /// @return The value.
    function loadCollValue() internal view returns (uint256) {
        return COLLATERAL_VALUE_STORAGE.asUint256().tload();
    }
}
