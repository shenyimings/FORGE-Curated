// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Ghosts} from "@test/recon/Ghosts.t.sol";
import {Properties} from "@test/recon/Properties.t.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/strategies/ERC4626StrategyVault.sol";

abstract contract ERC4626StrategyVaultTargets is BaseTargetFunctions, Properties {
  /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///

  /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

  function erc4626StrategyVault_approve(address spender, uint256 value) public asActor {
    erc4626StrategyVault.approve(spender, value);
  }

  function erc4626StrategyVault_deposit(uint256 assets, address receiver) public asActor {
    erc4626StrategyVault.deposit(assets, receiver);

    if (assets > 0) lte(erc4626StrategyVault.totalAssets(), erc4626StrategyVault.totalAssetsCap(), TOTAL_ASSETS_CAP_01);
  }

  function erc4626StrategyVault_mint(uint256 shares, address receiver) public asActor {
    erc4626StrategyVault.mint(shares, receiver);

    if (shares > 0) lte(erc4626StrategyVault.totalAssets(), erc4626StrategyVault.totalAssetsCap(), TOTAL_ASSETS_CAP_01);
  }

  function erc4626StrategyVault_pause() public asActor {
    erc4626StrategyVault.pause();
  }

  function erc4626StrategyVault_redeem(uint256 shares, address receiver, address owner) public asActor {
    erc4626StrategyVault.redeem(shares, receiver, owner);
  }

  function erc4626StrategyVault_setTotalAssetsCap(uint256 totalAssetsCap_) public asActor {
    if (totalAssetsCap_ != type(uint128).max) totalAssetsCap_ = between(totalAssetsCap_, 0, type(uint128).max);
    erc4626StrategyVault.setTotalAssetsCap(totalAssetsCap_);
  }

  function erc4626StrategyVault_transfer(address to, uint256 value) public asActor {
    erc4626StrategyVault.transfer(to, value);
  }

  function erc4626StrategyVault_transferFrom(address from, address to, uint256 value) public asActor {
    erc4626StrategyVault.transferFrom(from, to, value);
  }

  function erc4626StrategyVault_unpause() public asActor {
    erc4626StrategyVault.unpause();
  }

  function erc4626StrategyVault_withdraw(uint256 assets, address receiver, address owner) public asActor {
    erc4626StrategyVault.withdraw(assets, receiver, owner);
  }
}
