// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BridgeCoordinatorL1, PredepositCoordinator } from "../../src/BridgeCoordinatorL1.sol";
import { IBridgeAdapter } from "../../src/interfaces/IBridgeAdapter.sol";

import { BaseBridgeCoordinatorHarness } from "./BaseBridgeCoordinatorHarness.sol";

contract BridgeCoordinatorL1Harness is BaseBridgeCoordinatorHarness, BridgeCoordinatorL1 { }
