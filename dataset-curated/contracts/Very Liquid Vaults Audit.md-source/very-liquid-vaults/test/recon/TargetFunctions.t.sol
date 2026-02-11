// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Targets
// NOTE: Always import and apply them in alphabetical order, so much easier to debug!

import {AdminTargets} from "@test/recon/targets/AdminTargets.t.sol";

import {DoomsdayTargets} from "@test/recon/targets/DoomsdayTargets.t.sol";

import {ManagersTargets} from "@test/recon/targets/ManagersTargets.t.sol";
import {AaveStrategyVaultTargets} from "@test/recon/targets/project/AaveStrategyVaultTargets.t.sol";

import {AuthTargets} from "@test/recon/targets/project/AuthTargets.t.sol";
import {CashStrategyVaultTargets} from "@test/recon/targets/project/CashStrategyVaultTargets.t.sol";
import {ERC4626MustNotRevertTargets} from "@test/recon/targets/project/ERC4626MustNotRevertTargets.t.sol";
import {ERC4626StrategyVaultTargets} from "@test/recon/targets/project/ERC4626StrategyVaultTargets.t.sol";
import {SizeMetaVaultTargets} from "@test/recon/targets/project/SizeMetaVaultTargets.t.sol";

abstract contract TargetFunctions is
  AaveStrategyVaultTargets,
  AdminTargets,
  CashStrategyVaultTargets,
  DoomsdayTargets,
  AuthTargets,
  ERC4626MustNotRevertTargets,
  ERC4626StrategyVaultTargets,
  ManagersTargets,
  SizeMetaVaultTargets
{
/// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///

/// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
