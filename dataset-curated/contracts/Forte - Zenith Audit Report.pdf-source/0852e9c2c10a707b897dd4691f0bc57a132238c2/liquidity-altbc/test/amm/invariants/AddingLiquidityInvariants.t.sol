/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AddingLiquidityInvariants} from "liquidity-base/test/amm/invariants/AddingLiquidityInvariants.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import "forge-std/console2.sol";

contract ALTBCAddingLiquidityInvariants is AddingLiquidityInvariants, ALTBCTestSetup {}
