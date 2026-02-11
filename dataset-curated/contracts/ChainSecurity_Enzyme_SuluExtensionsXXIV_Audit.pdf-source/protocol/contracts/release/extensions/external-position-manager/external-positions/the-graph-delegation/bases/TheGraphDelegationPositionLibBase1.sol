// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

/// @title TheGraphDelegationPositionLibBase1 Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A persistent contract containing all required storage variables and
/// required functions for a TheGraphDelegationPositionLib implementation
/// @dev DO NOT EDIT CONTRACT. If new events or storage are necessary, they should be added to
/// a numbered TheGraphDelegationPositionLibBaseXXX that inherits the previous base.
/// e.g., `TheGraphDelegationPositionLibBase2 is TheGraphDelegationPositionLibBase1`

contract TheGraphDelegationPositionLibBase1 {
    event IndexerAdded(address indexed indexer);

    event IndexerRemoved(address indexed indexer);

    address[] internal indexers;
}
