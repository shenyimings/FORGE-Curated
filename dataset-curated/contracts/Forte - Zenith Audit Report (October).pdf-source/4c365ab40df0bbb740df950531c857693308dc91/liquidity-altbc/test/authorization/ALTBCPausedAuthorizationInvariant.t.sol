// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {pausedAuthorizationInvariants} from "liquidity-base/test/authorization/invariants/pausedAuthorizationInvariants.t.sol";

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

contract ALTBCPausedAuthorizationInvariants is pausedAuthorizationInvariants, ALTBCTestSetup {}
