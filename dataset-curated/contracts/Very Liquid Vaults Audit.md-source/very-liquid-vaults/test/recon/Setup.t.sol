// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm as hevm} from "@chimera/Hevm.sol";
import {Vm} from "forge-std/Vm.sol";

// Managers
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";

// Helpers
import {Utils} from "@recon/Utils.sol";

// Your deps

import {PropertiesConstants} from "@crytic/properties/contracts/util/PropertiesConstants.sol";
import "src/Auth.sol";
import "src/SizeMetaVault.sol";
import "src/strategies/AaveStrategyVault.sol";
import "src/strategies/CashStrategyVault.sol";
import "src/strategies/ERC4626StrategyVault.sol";

import {Setup as __Setup} from "@test/Setup.t.sol";

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils, __Setup, PropertiesConstants {
  Vm private vm = Vm(address(hevm));
  /// === Setup === ///
  /// This contains all calls to be performed in the tester constructor, both for Echidna and Foundry

  IERC4626[] internal vaults;

  function setup() internal virtual override {
    deploy(address(this));
    _addActor(USER1);
    _addActor(USER2);
    _addActor(USER3);
    _addAsset(address(erc20Asset));

    vaults.push(IERC4626(aaveStrategyVault));
    vaults.push(IERC4626(cashStrategyVault));
    vaults.push(IERC4626(erc4626StrategyVault));
    vaults.push(IERC4626(sizeMetaVault));
  }

  /// === MODIFIERS === ///
  /// Prank admin and actor

  modifier asAdmin() {
    vm.startPrank(address(this));
    _;
    vm.stopPrank();
  }

  modifier asActor() {
    vm.startPrank(address(_getActor()));
    _;
    vm.stopPrank();
  }
}
