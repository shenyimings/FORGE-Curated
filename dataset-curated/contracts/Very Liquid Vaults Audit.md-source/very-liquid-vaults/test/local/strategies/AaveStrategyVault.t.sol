// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";

import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Auth} from "@src/Auth.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";

import {IVault} from "@src//IVault.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

contract AaveStrategyVaultTest is BaseTest, Initializable {
  uint256 initialBalance;
  uint256 initialTotalAssets;
  bool expectRevert = false;

  function setUp() public override {
    super.setUp();
    initialTotalAssets = aaveStrategyVault.totalAssets();
    initialBalance = erc20Asset.balanceOf(address(aToken));
  }

  function test_AaveStrategyVault_initialize() public view {
    assertEq(address(aaveStrategyVault.pool()), address(pool));
    assertEq(address(aaveStrategyVault.aToken()), address(aToken));
  }

  function test_AaveStrategyVault_initialize_invalid_asset() public {
    vm.store(address(aaveStrategyVault), _initializableStorageSlot(), bytes32(uint256(0)));
    vm.prank(admin);
    vm.expectRevert(abi.encodeWithSelector(AaveStrategyVault.InvalidAsset.selector, address(weth)));
    aaveStrategyVault.initialize(auth, IERC20(address(weth)), "VAULT", "VAULT", address(this), FIRST_DEPOSIT_AMOUNT, pool);
  }

  function test_AaveStrategyVault_rebalance() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = aaveStrategyVault;
    strategies[1] = cashStrategyVault;
    strategies[2] = erc4626StrategyVault;
    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    _deposit(charlie, sizeMetaVault, 100e6);

    uint256 balanceBeforeAaveStrategyVault = aaveStrategyVault.totalAssets();
    uint256 balanceBeforeCashStrategyVault = cashStrategyVault.totalAssets();

    uint256 amount = 200e6;
    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), amount);
    vm.prank(alice);
    aaveStrategyVault.deposit(amount, alice);

    uint256 rebalanceAmount = 50e6;

    vm.prank(strategist);
    sizeMetaVault.rebalance(aaveStrategyVault, cashStrategyVault, rebalanceAmount, 0);

    assertEq(aaveStrategyVault.totalAssets(), balanceBeforeAaveStrategyVault + amount - rebalanceAmount);
    assertEq(cashStrategyVault.totalAssets(), balanceBeforeCashStrategyVault + rebalanceAmount);
  }

  function test_AaveStrategyVault_deposit_balanceOf_totalAssets() public {
    uint256 amount = 100e6;
    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), amount);
    vm.prank(alice);
    aaveStrategyVault.deposit(amount, alice);
    assertEq(aaveStrategyVault.balanceOf(alice), amount);
    assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + amount);
    assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + amount);
    assertEq(erc20Asset.balanceOf(alice), 0);
  }

  function test_AaveStrategyVault_deposit_withdraw() public {
    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
    vm.prank(alice);
    aaveStrategyVault.deposit(depositAmount, alice);
    assertEq(aaveStrategyVault.balanceOf(alice), depositAmount);
    assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + depositAmount);
    assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount);
    assertEq(erc20Asset.balanceOf(alice), 0);

    uint256 withdrawAmount = 30e6;
    vm.prank(alice);
    aaveStrategyVault.withdraw(withdrawAmount, alice, alice);
    assertEq(aaveStrategyVault.balanceOf(alice), depositAmount - withdrawAmount);
    assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + depositAmount - withdrawAmount);
    assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount - withdrawAmount);
    assertEq(erc20Asset.balanceOf(alice), withdrawAmount);
  }

  function test_AaveStrategyVault_deposit_rebalance_does_not_change_balanceOf() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = aaveStrategyVault;
    strategies[1] = cashStrategyVault;
    strategies[2] = erc4626StrategyVault;
    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    _deposit(charlie, sizeMetaVault, 100e6);

    uint256 balanceBeforeAaveStrategyVault = erc20Asset.balanceOf(address(aToken));

    uint256 depositAmount = 200e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
    vm.prank(alice);
    aaveStrategyVault.deposit(depositAmount, alice);
    uint256 shares = aaveStrategyVault.balanceOf(alice);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);

    uint256 balanceBeforeRebalanceCashStrategyVault = erc20Asset.balanceOf(address(cashStrategyVault));

    uint256 pullAmount = 30e6;
    vm.prank(strategist);
    sizeMetaVault.rebalance(aaveStrategyVault, cashStrategyVault, pullAmount, 0);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);
    assertEq(erc20Asset.balanceOf(address(aToken)), balanceBeforeAaveStrategyVault + depositAmount - pullAmount);
    assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), balanceBeforeRebalanceCashStrategyVault + pullAmount);
  }

  function test_AaveStrategyVault_deposit_rebalance_redeem() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = aaveStrategyVault;
    strategies[1] = cashStrategyVault;
    strategies[2] = erc4626StrategyVault;
    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    _deposit(charlie, sizeMetaVault, 100e6);

    uint256 balanceBeforeAaveStrategyVault = erc20Asset.balanceOf(address(aToken));

    uint256 depositAmount = 200e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
    vm.prank(alice);
    aaveStrategyVault.deposit(depositAmount, alice);
    uint256 shares = aaveStrategyVault.balanceOf(alice);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);

    uint256 balanceBeforeRebalance = erc20Asset.balanceOf(address(cashStrategyVault));

    uint256 pullAmount = 30e6;
    vm.prank(strategist);
    sizeMetaVault.rebalance(aaveStrategyVault, cashStrategyVault, pullAmount, 0);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);
    assertEq(erc20Asset.balanceOf(address(aToken)), balanceBeforeAaveStrategyVault + depositAmount - pullAmount);
    assertEq(erc20Asset.balanceOf(address(cashStrategyVault)), balanceBeforeRebalance + pullAmount);

    uint256 maxRedeem = aaveStrategyVault.maxRedeem(alice);
    uint256 previewRedeem = aaveStrategyVault.previewRedeem(maxRedeem);

    vm.prank(alice);
    aaveStrategyVault.redeem(maxRedeem, alice, alice);
    assertEq(aaveStrategyVault.balanceOf(alice), shares - maxRedeem);
    assertEq(erc20Asset.balanceOf(alice), previewRedeem);
  }

  function test_AaveStrategyVault_deposit_donate_withdraw() public {
    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
    vm.prank(alice);
    aaveStrategyVault.deposit(depositAmount, alice);
    uint256 shares = aaveStrategyVault.balanceOf(alice);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);

    uint256 donation = 30e6;
    _mint(erc20Asset, bob, donation);
    vm.prank(bob);
    erc20Asset.transfer(address(aToken), donation);
    vm.prank(admin);
    pool.setLiquidityIndex(address(erc20Asset), ((depositAmount + donation) * 1e27) / depositAmount);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);
    assertEq(aaveStrategyVault.balanceOf(bob), 0);
    assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount + donation);

    uint256 maxWithdraw = aaveStrategyVault.maxWithdraw(alice);

    vm.prank(alice);
    aaveStrategyVault.withdraw(maxWithdraw, alice, alice);
    assertEq(aaveStrategyVault.balanceOf(alice), 0);
    assertGe(aaveStrategyVault.totalAssets(), initialTotalAssets);
    assertGe(erc20Asset.balanceOf(address(aToken)), initialBalance);
    assertEq(erc20Asset.balanceOf(alice), maxWithdraw);
  }

  function test_AaveStrategyVault_deposit_donate_redeem() public {
    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
    vm.prank(alice);
    aaveStrategyVault.deposit(depositAmount, alice);
    uint256 shares = aaveStrategyVault.balanceOf(alice);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);

    uint256 donation = 30e6;
    _mint(erc20Asset, bob, donation);
    vm.prank(bob);
    erc20Asset.transfer(address(aToken), donation);
    vm.prank(admin);
    pool.setLiquidityIndex(address(erc20Asset), ((depositAmount + donation) * 1e27) / depositAmount);
    assertEq(aaveStrategyVault.balanceOf(alice), shares);
    assertEq(aaveStrategyVault.balanceOf(bob), 0);
    assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount + donation);

    vm.prank(alice);
    aaveStrategyVault.redeem(shares, alice, alice);
    assertEq(aaveStrategyVault.balanceOf(alice), 0);
    assertGe(aaveStrategyVault.totalAssets(), initialTotalAssets);
    assertGe(erc20Asset.balanceOf(address(aToken)), initialBalance);
  }

  function test_AaveStrategyVault_initialize_wiht_address_zero_pool_must_revert() public {
    _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

    address AuthImplementation = address(new Auth());
    Auth auth = Auth(payable(new ERC1967Proxy(AuthImplementation, abi.encodeWithSelector(Auth.initialize.selector, bob))));

    _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

    address AaveStrategyVaultImplementation = address(new AaveStrategyVault());

    vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
    vm.prank(alice);
    AaveStrategyVault(
      payable(
        new ERC1967Proxy(AaveStrategyVaultImplementation, abi.encodeCall(AaveStrategyVault.initialize, (auth, erc20Asset, "VAULT", "VAULT", address(this), FIRST_DEPOSIT_AMOUNT, IPool(address(0)))))
      )
    );
  }

  function test_AaveStrategyVault_maxDeposit_no_config() public {
    vm.prank(admin);
    pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: 0}));

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxWithdraw(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxRedeem(address(erc20Asset)), 0);
  }

  function test_AaveStrategyVault_maxDeposit_paused() public {
    vm.prank(admin);
    pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: 1 << 60}));

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxWithdraw(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxRedeem(address(erc20Asset)), 0);
  }

  function test_AaveStrategyVault_maxDeposit_supply_cap_0() public {
    uint8 decimals = erc20Asset.decimals();
    uint256 totalAssetsBefore = aaveStrategyVault.totalAssets();

    vm.prank(admin);
    pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48)}));

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), type(uint256).max);
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), type(uint256).max);

    uint256 totalAssetsCap = 30e6;
    vm.prank(admin);
    aaveStrategyVault.setTotalAssetsCap(totalAssetsCap);

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), Math.saturatingSub(totalAssetsCap, totalAssetsBefore));
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), Math.saturatingSub(totalAssetsCap, totalAssetsBefore));
  }

  function test_AaveStrategyVault_maxDeposit_supply_cap() public {
    uint8 decimals = erc20Asset.decimals();
    uint256 supplyCap = 42;

    vm.prank(admin);
    pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48) | (supplyCap << 116)}));

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), 0);
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), 0);

    supplyCap = 100e6;

    vm.prank(admin);
    pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48) | (supplyCap << 116)}));

    uint256 totalSupply = aToken.totalSupply();

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), supplyCap - totalSupply);
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), supplyCap - totalSupply);
  }

  function test_AaveStrategyVault_maxDeposit_totalAssetsCap_supply_cap() public {
    uint256 totalAssetsBefore = aaveStrategyVault.totalAssets();

    uint256 totalAssetsCap = 30e6;
    vm.prank(admin);
    aaveStrategyVault.setTotalAssetsCap(totalAssetsCap);

    uint8 decimals = erc20Asset.decimals();
    uint256 supplyCap = 100e6;

    vm.prank(admin);
    pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48) | (supplyCap << 116)}));

    assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), Math.saturatingSub(totalAssetsCap, totalAssetsBefore));
    assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), Math.saturatingSub(totalAssetsCap, totalAssetsBefore));
  }

  function test_AaveStrategyVault_maxWithdraw_maxRedeem() public {
    uint256 assetsBefore = aaveStrategyVault.convertToAssets(aaveStrategyVault.balanceOf(address(sizeMetaVault)));
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = aaveStrategyVault;
    strategies[1] = cashStrategyVault;
    strategies[2] = erc4626StrategyVault;
    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    _deposit(alice, aaveStrategyVault, 100e6);
    _deposit(bob, sizeMetaVault, 30e6);

    assertEq(aaveStrategyVault.maxWithdraw(address(sizeMetaVault)), assetsBefore + 30e6);
    assertEq(aaveStrategyVault.maxRedeem(address(sizeMetaVault)), aaveStrategyVault.previewRedeem(assetsBefore + 30e6));
  }

  function testFuzz_AaveStrategyVault_deposit_assets_shares_0_reverts(uint256 amount, uint256 index1) public {
    amount = bound(amount, 1, 100e6);
    index1 = bound(index1, 1e27, 1.3e27);

    _mint(erc20Asset, address(aaveStrategyVault), amount * 2);
    _setLiquidityIndex(erc20Asset, index1);

    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(aaveStrategyVault), amount);

    vm.prank(alice);
    try aaveStrategyVault.deposit(amount, alice) {
      index1 = bound(index1, 2 * index1, 10 * index1);
      _setLiquidityIndex(erc20Asset, index1);

      vm.prank(alice);
      aaveStrategyVault.redeem(1, alice, alice);
    } catch (bytes memory err) {
      assertEq(bytes4(err), BaseVault.NullAmount.selector);
    }
  }

  function test_AaveStrategyVault_deposit_assets_shares_0_reverts_concrete() public {
    testFuzz_AaveStrategyVault_deposit_assets_shares_0_reverts(1, 1_198_633_698_108_951_810_697_775_384);
  }
}
