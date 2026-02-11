// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

/// @title MorphoBluePositionLibBase1 Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A persistent contract containing all required storage variables and
/// required functions for a MorphoBluePositionLib implementation
/// @dev DO NOT EDIT CONTRACT. If new events or storage are necessary, they should be added to
/// a numbered MorphoBluePositionLibBaseXXX that inherits the previous base.
/// e.g., `MorphoBluePositionLibBase2 is MorphoBluePositionLibBase1`
abstract contract MorphoBluePositionLibBase1 {
    event MarketIdAdded(bytes32 indexed marketId);

    event MarketIdRemoved(bytes32 indexed marketId);

    bytes32[] internal marketIds;
}
