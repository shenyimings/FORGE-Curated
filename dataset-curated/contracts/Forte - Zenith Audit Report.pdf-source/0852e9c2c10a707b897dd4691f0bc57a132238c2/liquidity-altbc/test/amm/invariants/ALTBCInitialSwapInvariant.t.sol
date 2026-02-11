/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {InitialSwapInvariant} from "liquidity-base/test/amm/invariants/InitialSwapInvariant.t.sol";

contract ALTBCInitialSwapInvariant is InitialSwapInvariant, ALTBCTestSetup {}
