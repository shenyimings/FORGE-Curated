// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Ghosts} from "@test/recon/Ghosts.t.sol";
import {Properties} from "@test/recon/Properties.t.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

abstract contract DoomsdayTargets is BaseTargetFunctions, Properties {
  /// Makes a handler have no side effects
  /// The fuzzer will call this anyway, and because it reverts it will be removed from shrinking
  /// Replace the "withGhosts" with "stateless" to make the code clean
  modifier stateless() {
    _;
    revert("stateless");
  }
}
