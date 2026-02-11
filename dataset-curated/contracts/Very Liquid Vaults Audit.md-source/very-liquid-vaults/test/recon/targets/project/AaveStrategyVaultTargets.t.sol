// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Ghosts} from "@test/recon/Ghosts.t.sol";
import {Properties} from "@test/recon/Properties.t.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/strategies/AaveStrategyVault.sol";

abstract contract AaveStrategyVaultTargets is BaseTargetFunctions, Properties {
  /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///

  /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

  function aaveStrategyVault_approve(address spender, uint256 value) public asActor {
    aaveStrategyVault.approve(spender, value);
  }

  function aaveStrategyVault_deposit(uint256 assets, address receiver) public asActor {
    aaveStrategyVault.deposit(assets, receiver);

    if (assets > 0) lte(aaveStrategyVault.totalAssets(), aaveStrategyVault.totalAssetsCap(), TOTAL_ASSETS_CAP_01);
  }

  function aaveStrategyVault_mint(uint256 shares, address receiver) public asActor {
    aaveStrategyVault.mint(shares, receiver);

    if (shares > 0) lte(aaveStrategyVault.totalAssets(), aaveStrategyVault.totalAssetsCap(), TOTAL_ASSETS_CAP_01);
  }

  function aaveStrategyVault_pause() public asActor {
    aaveStrategyVault.pause();
  }

  function aaveStrategyVault_redeem(uint256 shares, address receiver, address owner) public asActor {
    aaveStrategyVault.redeem(shares, receiver, owner);
  }

  function aaveStrategyVault_setTotalAssetsCap(uint256 totalAssetsCap_) public asActor {
    if (totalAssetsCap_ != type(uint128).max) totalAssetsCap_ = between(totalAssetsCap_, 0, type(uint128).max);
    aaveStrategyVault.setTotalAssetsCap(totalAssetsCap_);
  }

  function aaveStrategyVault_transfer(address to, uint256 value) public asActor {
    aaveStrategyVault.transfer(to, value);
  }

  function aaveStrategyVault_transferFrom(address from, address to, uint256 value) public asActor {
    aaveStrategyVault.transferFrom(from, to, value);
  }

  function aaveStrategyVault_unpause() public asActor {
    aaveStrategyVault.unpause();
  }

  function aaveStrategyVault_withdraw(uint256 assets, address receiver, address owner) public asActor {
    aaveStrategyVault.withdraw(assets, receiver, owner);
  }
}
