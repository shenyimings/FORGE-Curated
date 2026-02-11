// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

/// @title AaveDebtPositionLibBase1 Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A persistent contract containing all required storage variables and
/// required functions for a AaveDebtPositionLib implementation
/// @dev DO NOT EDIT CONTRACT. If new events or storage are necessary, they should be added to
/// a numbered AaveDebtPositionLibBaseXXX that inherits the previous base.
/// e.g., `AaveDebtPositionLibBase2 is AaveDebtPositionLibBase1`

contract AaveDebtPositionLibBase1 {
    event BorrowedAssetAdded(address indexed asset);

    event BorrowedAssetRemoved(address indexed asset);

    event CollateralAssetAdded(address indexed asset);

    event CollateralAssetRemoved(address indexed asset);

    address[] internal borrowedAssets;
    address[] internal collateralAssets;

    // Rather than storing a boolean, stores the associated debt token to save gas for future lookups
    mapping(address => address) internal borrowedAssetToDebtToken;
}
