// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {SwapInvariants} from "liquidity-base/test/amm/invariants/SwapInvariants.t.sol";

contract ALTBCSwapInvariants is ALTBCTestSetup, SwapInvariants {}
