// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Users } from "./Types.sol";

/// @notice Contract with default values used throughout the tests.
contract Defaults {
    //----------------------------------------
    // Constants
    //----------------------------------------

    uint256 public constant INITIAL_BALANCE = 100_000e18;
    uint256 public constant DEFAULT_MINT_AMOUNT = 100e18;
    uint64 public constant DEFAULT_TIME_LOCK_DURATION = 28 days;
    uint256 public constant DEFAULT_PENALTY_PERCENTAGE = 1e18;

    uint32 public constant mainEid = 1;

    //----------------------------------------
    // State variables
    //----------------------------------------

    Users internal users;
}
