/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestCommon} from "test/util/TestCommon.sol";
import {TestConstants} from "test/util/TestConstants.sol";

abstract contract EquationBase is TestCommon, TestConstants {
    uint256 constant MAX_SUPPLY = 1e11 * ERC20_DECIMALS;
}
