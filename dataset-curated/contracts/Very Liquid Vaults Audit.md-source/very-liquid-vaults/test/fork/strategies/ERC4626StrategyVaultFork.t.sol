// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ForkTest} from "@test/fork/ForkTest.t.sol";

contract ERC4626StrategyVaultForkTest is ForkTest {
  using SafeERC20 for IERC20Metadata;

  function testFork_ERC4626StrategyVault_deposit_withdraw_with_interest() public {
    uint256 amount = 10 * 10 ** erc20Asset.decimals();

    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(erc4626StrategyVault), amount);

    vm.startPrank(alice);

    erc4626StrategyVault.deposit(amount, alice);

    vm.warp(block.timestamp + 1 weeks);

    uint256 maxRedeem = erc4626StrategyVault.maxRedeem(alice);
    uint256 redeemedAssets = erc4626StrategyVault.redeem(maxRedeem, alice, alice);

    assertGt(redeemedAssets, amount);
  }

  function testFork_ERC4626StrategyVault_deposit_withdraw_with_interest_2() public {
    uint256 amount = 10 * 10 ** erc20Asset.decimals();

    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(erc4626StrategyVault2), amount);

    vm.startPrank(alice);

    erc4626StrategyVault2.deposit(amount, alice);

    vm.warp(block.timestamp + 1 weeks);

    uint256 maxRedeem = erc4626StrategyVault2.maxRedeem(alice);
    uint256 redeemedAssets = erc4626StrategyVault2.redeem(maxRedeem, alice, alice);

    assertGt(redeemedAssets, amount);
  }
}
