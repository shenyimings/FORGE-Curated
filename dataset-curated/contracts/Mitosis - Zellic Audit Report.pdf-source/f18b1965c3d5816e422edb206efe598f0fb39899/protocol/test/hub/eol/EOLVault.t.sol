// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import { Test } from '@std/Test.sol';

import { WETH } from '@solady/tokens/WETH.sol';
import { ERC1967Factory } from '@solady/utils/ERC1967Factory.sol';

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';

import { EOLVault } from '../../../src/hub/eol/EOLVault.sol';

contract EOLVaultTest is Test {
  address owner = makeAddr('owner');
  address user = makeAddr('user');

  WETH weth;

  ERC1967Factory factory;
  EOLVault vault;

  function setUp() public {
    weth = new WETH();
    factory = new ERC1967Factory();

    vault = EOLVault(
      factory.deployAndCall(
        address(new EOLVault()), //
        owner,
        abi.encodeCall(EOLVault.initialize, (owner, IERC20Metadata(address(weth)), 'Mitosis EOL Wrapped ETH', 'miwETH'))
      )
    );
  }

  function test_init() public view {
    assertEq(vault.name(), 'Mitosis EOL Wrapped ETH');
    assertEq(vault.symbol(), 'miwETH');
    assertEq(vault.decimals(), 18);
    assertEq(vault.asset(), address(weth));
    assertEq(vault.owner(), owner);
  }

  function test_deposit() public {
    vm.deal(user, 100 ether);
    vm.startPrank(user);
    weth.deposit{ value: 100 ether }();
    weth.approve(address(vault), 100 ether);
    vault.deposit(100 ether, user);
    vm.stopPrank();

    assertEq(vault.balanceOf(user), 100 ether);
    assertEq(vault.totalAssets(), 100 ether);
    assertEq(vault.totalSupply(), 100 ether);
  }

  function test_mint() public {
    vm.deal(user, 100 ether);
    vm.startPrank(user);
    weth.deposit{ value: 100 ether }();
    weth.approve(address(vault), 100 ether);
    vault.mint(100 ether, user);
    vm.stopPrank();

    assertEq(vault.balanceOf(user), 100 ether);
    assertEq(vault.totalAssets(), 100 ether);
    assertEq(vault.totalSupply(), 100 ether);
  }

  function test_withdraw() public {
    test_deposit();

    vm.prank(user);
    vault.withdraw(100 ether, owner, user);

    assertEq(vault.balanceOf(user), 0);
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(weth.balanceOf(address(vault)), 0);
    assertEq(weth.balanceOf(owner), 100 ether);
  }

  function test_redeem() public {
    test_mint();

    vm.prank(user);
    vault.redeem(100 ether, owner, user);

    assertEq(vault.balanceOf(user), 0);
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(weth.balanceOf(address(vault)), 0);
    assertEq(weth.balanceOf(owner), 100 ether);
  }
}
