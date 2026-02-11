/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {RemovingLiquidityInvariants} from "liquidity-base/test/amm/invariants/RemovingLiquidityInvariants.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import "forge-std/console2.sol";

contract ALTBCRemovingLiquidityInvariants is RemovingLiquidityInvariants, ALTBCTestSetup {}
