// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import { IRamsesV2PoolImmutables } from
    "contracts/interfaces/external/ramses/IRamsesV2PoolImmutables.sol";
import { IRamsesV2PoolState } from
    "contracts/interfaces/external/ramses/IRamsesV2PoolState.sol";

/// @title The interface for a Ramses V2 Pool
/// @notice A Ramses pool facilitates swapping and automated market making
/// between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IRamsesV2Pool is IRamsesV2PoolImmutables, IRamsesV2PoolState {
    /// @notice Initializes a pool with parameters provided
    function initialize(
        address _factory,
        address _nfpManager,
        address _veRam,
        address _voter,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) external;

    function _advancePeriod() external;
}
