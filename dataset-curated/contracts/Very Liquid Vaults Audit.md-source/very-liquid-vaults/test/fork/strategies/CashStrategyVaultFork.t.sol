// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ForkTest} from "@test/fork/ForkTest.t.sol";

contract CashStrategyVaultForkTest is ForkTest {
  using SafeERC20 for IERC20Metadata;

  function testFork_CashStrategyVault_increase_assets_if_donated() public {
    uint256 amount = 10 * 10 ** erc20Asset.decimals();

    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(cashStrategyVault), amount);

    vm.startPrank(alice);

    cashStrategyVault.deposit(amount, alice);

    uint256 balanceOfBefore = erc20Asset.balanceOf(address(cashStrategyVault));
    _mint(erc20Asset, address(cashStrategyVault), balanceOfBefore * 2);

    uint256 assetsAfter = cashStrategyVault.convertToAssets(cashStrategyVault.balanceOf(alice));

    assertApproxEqAbs(assetsAfter, 2 * amount, 1);
  }
}
