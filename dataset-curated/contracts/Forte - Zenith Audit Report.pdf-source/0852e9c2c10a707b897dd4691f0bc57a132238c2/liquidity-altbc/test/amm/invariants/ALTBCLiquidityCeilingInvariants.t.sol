/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LiquidityCeilingInvariants} from "liquidity-base/test/amm/invariants/LiquidityCeilingInvariant.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

contract ALTBCLiquidityCeilingInvariant is LiquidityCeilingInvariants, ALTBCTestSetup {}
