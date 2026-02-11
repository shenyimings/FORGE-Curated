// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import "./pool/IV3PoolImmutables.sol";
import "./pool/IV3PoolState.sol";
import "./pool/IV3PoolDerivedState.sol";
import "./pool/IV3PoolActions.sol";
import "./pool/IV3PoolOwnerActions.sol";
import "./pool/IV3PoolEvents.sol";

/// @title The interface for a  V3 Pool
/// @notice A  pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IV3Pool is
    IV3PoolImmutables,
    IV3PoolState,
    IV3PoolDerivedState,
    IV3PoolActions,
    IV3PoolOwnerActions,
    IV3PoolEvents
{}
