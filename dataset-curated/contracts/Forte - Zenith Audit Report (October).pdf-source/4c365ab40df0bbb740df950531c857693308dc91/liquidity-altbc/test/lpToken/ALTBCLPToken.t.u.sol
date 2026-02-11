// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {LPTokenTest} from "lib/liquidity-base/test/lpToken/LPToken.t.u.sol";

contract ALTBCLPTokenTest is LPTokenTest, ALTBCTestSetup {}
