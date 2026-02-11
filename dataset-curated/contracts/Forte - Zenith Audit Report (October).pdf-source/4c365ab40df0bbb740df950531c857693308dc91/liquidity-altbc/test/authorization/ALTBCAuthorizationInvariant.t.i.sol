// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {authorizationInvariants} from "liquidity-base/test/authorization/invariants/authorizationInvariant.t.sol";

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

contract ALTBCAuthorizationInvariants is authorizationInvariants, ALTBCTestSetup {}
