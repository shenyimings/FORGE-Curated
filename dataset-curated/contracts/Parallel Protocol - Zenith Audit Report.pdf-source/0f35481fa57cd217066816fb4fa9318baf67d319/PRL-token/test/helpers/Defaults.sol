// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Users } from "./Types.sol";

/// @notice Contract with default values used throughout the tests.
contract Defaults {
    //----------------------------------------
    // Constants
    //----------------------------------------

    uint256 public constant ONE_DAY_IN_SECONDS = 1 days;
    uint256 public constant DEFAULT_PRL_SUPPLY = 1_000_000_000e18;
    uint256 public constant INITIAL_BALANCE = 100_000e18;
    uint256 public constant DEFAULT_AMOUNT_MIGRATED = 1000e18;

    uint32 public constant mainEid = 1;
    uint32 public constant aEid = 2;
    uint32 public constant bEid = 3;
    //----------------------------------------
    // State variables
    //----------------------------------------

    Users internal users;
}
