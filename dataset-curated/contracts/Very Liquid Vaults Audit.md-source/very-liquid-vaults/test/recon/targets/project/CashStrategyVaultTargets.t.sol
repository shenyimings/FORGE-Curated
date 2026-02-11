// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Ghosts} from "@test/recon/Ghosts.t.sol";
import {Properties} from "@test/recon/Properties.t.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/strategies/CashStrategyVault.sol";

abstract contract CashStrategyVaultTargets is BaseTargetFunctions, Properties {
  /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///

  /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

  function cashStrategyVault_approve(address spender, uint256 value) public asActor {
    cashStrategyVault.approve(spender, value);
  }

  function cashStrategyVault_deposit(uint256 assets, address receiver) public asActor {
    cashStrategyVault.deposit(assets, receiver);

    if (assets > 0) lte(cashStrategyVault.totalAssets(), cashStrategyVault.totalAssetsCap(), TOTAL_ASSETS_CAP_01);
  }

  function cashStrategyVault_mint(uint256 shares, address receiver) public asActor {
    cashStrategyVault.mint(shares, receiver);

    if (shares > 0) lte(cashStrategyVault.totalAssets(), cashStrategyVault.totalAssetsCap(), TOTAL_ASSETS_CAP_01);
  }

  function cashStrategyVault_pause() public asActor {
    cashStrategyVault.pause();
  }

  function cashStrategyVault_redeem(uint256 shares, address receiver, address owner) public asActor {
    cashStrategyVault.redeem(shares, receiver, owner);
  }

  function cashStrategyVault_setTotalAssetsCap(uint256 totalAssetsCap_) public asActor {
    if (totalAssetsCap_ != type(uint128).max) totalAssetsCap_ = between(totalAssetsCap_, 0, type(uint128).max);
    cashStrategyVault.setTotalAssetsCap(totalAssetsCap_);
  }

  function cashStrategyVault_transfer(address to, uint256 value) public asActor {
    cashStrategyVault.transfer(to, value);
  }

  function cashStrategyVault_transferFrom(address from, address to, uint256 value) public asActor {
    cashStrategyVault.transferFrom(from, to, value);
  }

  function cashStrategyVault_unpause() public asActor {
    cashStrategyVault.unpause();
  }

  function cashStrategyVault_withdraw(uint256 assets, address receiver, address owner) public asActor {
    cashStrategyVault.withdraw(assets, receiver, owner);
  }
}
