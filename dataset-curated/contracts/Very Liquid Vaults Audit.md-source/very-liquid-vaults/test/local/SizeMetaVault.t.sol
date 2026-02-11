// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC4626Mock} from "@openzeppelin/contracts/mocks/token/ERC4626Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626StrategyVaultScript} from "@script/ERC4626StrategyVault.s.sol";
import {Auth} from "@src/Auth.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {ERC4626StrategyVault} from "@src/strategies/ERC4626StrategyVault.sol";

import {IVault} from "@src//IVault.sol";
import {IVault} from "@src//IVault.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";
import {VaultMockAssetFeeOnDeposit} from "@test/mocks/VaultMockAssetFeeOnDeposit.t.sol";
import {VaultMockAssetFeeOnWithdraw} from "@test/mocks/VaultMockAssetFeeOnWithdraw.t.sol";
import {VaultMockRevertOnDeposit} from "@test/mocks/VaultMockRevertOnDeposit.t.sol";
import {VaultMockRevertOnWithdraw} from "@test/mocks/VaultMockRevertOnWithdraw.t.sol";

import {console} from "forge-std/console.sol";

contract SizeMetaVaultTest is BaseTest {
  bool public expectRevert = false;

  enum VaultType {
    REVERT_ON_DEPOSIT,
    REVERT_ON_WITHDRAW,
    ASSET_FEE_ON_DEPOSIT,
    ASSET_FEE_ON_WITHDRAW
  }

  VaultMockRevertOnDeposit vault_revertDeposit;
  VaultMockRevertOnWithdraw vault_revertWithdraw;
  VaultMockAssetFeeOnDeposit vault_assetFeeOnDeposit;
  VaultMockAssetFeeOnWithdraw vault_assetFeeOnWithdraw;

  function test_SizeMetaVault_initialize() public view {
    assertEq(address(sizeMetaVault.asset()), address(erc20Asset));
    assertEq(sizeMetaVault.name(), string.concat("Size Meta ", erc20Asset.name(), " Vault"));
    assertEq(sizeMetaVault.symbol(), string.concat("szMeta", erc20Asset.symbol()));
    assertEq(sizeMetaVault.decimals(), erc20Asset.decimals());
    assertEq(sizeMetaVault.totalSupply(), sizeMetaVault.strategiesCount() * FIRST_DEPOSIT_AMOUNT + 1);
    assertEq(sizeMetaVault.balanceOf(address(this)), 0);
    assertEq(sizeMetaVault.allowance(address(this), address(this)), 0);
    assertEq(sizeMetaVault.decimals(), erc20Asset.decimals());
    assertEq(sizeMetaVault.decimals(), erc20Asset.decimals());
    assertEq(sizeMetaVault.strategies().length, 3);
    assertEq(sizeMetaVault.rebalanceMaxSlippagePercent(), 0.01e18);
  }

  function test_SizeMetaVault_rebalance_cashStrategy_to_erc4626() public {
    uint256 cashAssetsBefore = cashStrategyVault.convertToAssets(cashStrategyVault.balanceOf(address(sizeMetaVault)));
    uint256 erc4626AssetsBefore = erc4626StrategyVault.totalAssets();

    uint256 amount = cashAssetsBefore;

    vm.prank(strategist);
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, amount, 0);

    uint256 cashAssetsAfter = cashStrategyVault.convertToAssets(cashStrategyVault.balanceOf(address(sizeMetaVault)));
    uint256 erc4626AssetsAfter = erc4626StrategyVault.totalAssets();

    assertEq(cashAssetsAfter, 0);
    assertEq(erc4626AssetsAfter, erc4626AssetsBefore + amount);
  }

  function test_SizeMetaVault_rebalance_erc4626_to_cashStrategy() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = erc4626StrategyVault;
    strategies[1] = cashStrategyVault;
    strategies[2] = aaveStrategyVault;

    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    _deposit(alice, sizeMetaVault, 100e6);

    uint256 erc4626AssetsBefore = erc4626StrategyVault.convertToAssets(erc4626StrategyVault.balanceOf(address(sizeMetaVault)));
    uint256 cashAssetsBefore = cashStrategyVault.convertToAssets(cashStrategyVault.balanceOf(address(sizeMetaVault)));

    uint256 amount = erc4626AssetsBefore;

    vm.prank(strategist);
    sizeMetaVault.rebalance(erc4626StrategyVault, cashStrategyVault, amount, 0);

    uint256 erc4626AssetsAfter = erc4626StrategyVault.convertToAssets(erc4626StrategyVault.balanceOf(address(sizeMetaVault)));
    uint256 cashAssetsAfter = cashStrategyVault.convertToAssets(cashStrategyVault.balanceOf(address(sizeMetaVault)));

    assertEq(erc4626AssetsAfter, 0);
    assertEq(cashAssetsAfter, cashAssetsBefore + amount);
  }

  function testFuzz_SizeMetaVault_rebalance_slippage_validation(uint256 amount, uint256 index) public {
    _setupSimpleConfiguration();

    IVault strategyFrom = cashStrategyVault;
    IVault strategyTo = aaveStrategyVault;

    amount = bound(amount, 10e6, 100e6);
    index = bound(index, 1e27, 1.3e27);

    _mint(erc20Asset, address(strategyFrom), amount * 2);
    _setLiquidityIndex(erc20Asset, index);

    vm.prank(strategist);
    try sizeMetaVault.rebalance(strategyFrom, strategyTo, amount, 0) {
      assertEq(expectRevert, false);
    } catch (bytes memory err) {
      assertEq(bytes4(err), SizeMetaVault.TransferredAmountLessThanMin.selector);
    }
  }

  function test_SizeMetaVault_rebalance_slippage_validation_concrete() public {
    expectRevert = true;
    testFuzz_SizeMetaVault_rebalance_slippage_validation(90_014_716, 1_200_000_000_000_000_000_000_018_340);
  }

  function test_SizeMetaVault_rebalance_with_slippage() public {
    _setupSimpleConfiguration();

    uint256 amount = 30e6;

    _mint(erc20Asset, address(cashStrategyVault), amount * 2);

    vm.prank(admin);
    sizeMetaVault.setRebalanceMaxSlippagePercent(0.02e18);

    vm.prank(admin);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidMaxSlippagePercent.selector, 1.5e18));
    sizeMetaVault.setRebalanceMaxSlippagePercent(1.5e18);

    vm.prank(strategist);
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, amount, 0.01e18);
  }

  function test_SizeMetaVault_addStrategy_validation() public {
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
    sizeMetaVault.addStrategy(IVault(address(0)));

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(erc4626StrategyVault)));
    sizeMetaVault.addStrategy(erc4626StrategyVault);
  }

  function test_SizeMetaVault_removeStrategy_validation() public {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(0)));
    sizeMetaVault.removeStrategy(IVault(address(0)), IVault(address(0)), type(uint256).max, 0);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cryticCashStrategyVault)));
    sizeMetaVault.removeStrategy(cryticCashStrategyVault, cashStrategyVault, type(uint256).max, 0);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cryticCashStrategyVault)));
    sizeMetaVault.removeStrategy(cashStrategyVault, cryticCashStrategyVault, type(uint256).max, 0);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cashStrategyVault)));
    sizeMetaVault.removeStrategy(cashStrategyVault, cashStrategyVault, type(uint256).max, 0);
  }

  function test_SizeMetaVault_reorderStrategies_validation() public {
    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.ArrayLengthMismatch.selector, 3, 0));
    sizeMetaVault.reorderStrategies(new IVault[](0));

    IVault[] memory strategiesWithZero = new IVault[](3);
    strategiesWithZero[0] = cryticCashStrategyVault;
    strategiesWithZero[1] = cryticAaveStrategyVault;
    strategiesWithZero[2] = cryticERC4626StrategyVault;

    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cryticCashStrategyVault)));
    sizeMetaVault.reorderStrategies(strategiesWithZero);

    IVault[] memory duplicates = new IVault[](3);
    duplicates[0] = cashStrategyVault;
    duplicates[1] = erc4626StrategyVault;
    duplicates[2] = cashStrategyVault;

    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cashStrategyVault)));
    sizeMetaVault.reorderStrategies(duplicates);
  }

  function test_SizeMetaVault_rebalance_validation() public {
    uint256 cashAssetsBefore = cashStrategyVault.totalAssets();

    uint256 amount = 5e6;

    // invalid strategyFrom reverts
    vm.prank(strategist);
    vm.expectRevert();
    sizeMetaVault.rebalance(IVault(address(1)), erc4626StrategyVault, amount, 0);

    // validate strategyTo
    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(1)));
    sizeMetaVault.rebalance(cashStrategyVault, IVault(address(1)), amount, 0);

    // validate amount 0
    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAmount.selector));
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, 0, 0);

    // validate amount > balance
    amount = 50e6;
    assertLt(cashAssetsBefore, amount);

    vm.prank(strategist);
    vm.expectRevert();
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, amount, 0);
  }

  function test_SizeMetaVault_rebalance() public {
    _setupSimpleConfiguration();

    uint256 cashAssetsBefore = cashStrategyVault.totalAssets();
    uint256 erc4626AssetsBefore = erc4626StrategyVault.totalAssets();

    uint256 amount = 50e6;
    assertLt(cashAssetsBefore, amount);

    vm.expectRevert();
    vm.prank(strategist);
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, amount, 0);

    vm.prank(strategist);
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, 5e6, 0);
    assertEq(cashStrategyVault.totalAssets(), cashAssetsBefore - 5e6);
    assertEq(erc4626StrategyVault.totalAssets(), erc4626AssetsBefore + 5e6);
  }

  function test_SizeMetaVault_rebalance_strategyFrom_not_added_must_revert() public {
    _deposit(alice, sizeMetaVault, 100e6);
    // remove cashStrategyVault; check removal; try to transfer from it
    uint256 lengthBefore = sizeMetaVault.strategiesCount();
    uint256 cashAssets = cashStrategyVault.totalAssets();

    vm.prank(guardian);
    sizeMetaVault.removeStrategy(cashStrategyVault, erc4626StrategyVault, type(uint256).max, 0);

    _mint(erc20Asset, address(cashStrategyVault), 2 * cashAssets);

    uint256 lengthAfter = sizeMetaVault.strategiesCount();
    assertEq(lengthBefore - 1, lengthAfter);

    _deposit(bob, cashStrategyVault, 40e6);
    uint256 bobBalanceBefore = cashStrategyVault.balanceOf(bob);
    vm.prank(bob);
    cashStrategyVault.transfer(address(sizeMetaVault), bobBalanceBefore);

    uint256 assetsToTransfer = cashStrategyVault.balanceOf(address(sizeMetaVault));

    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cashStrategyVault)));
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, assetsToTransfer, 0);
  }

  function test_SizeMetaVault_rebalance_strategyTo_not_added_must_revert() public {
    // remove erc4626StrategyVault; check removal; try to transfer to it
    uint256 lengthBefore = sizeMetaVault.strategiesCount();
    uint256 cashAssets = cashStrategyVault.totalAssets();

    vm.prank(guardian);
    sizeMetaVault.removeStrategy(erc4626StrategyVault, aaveStrategyVault, type(uint256).max, 0);

    uint256 lengthAfter = sizeMetaVault.strategiesCount();
    assertEq(lengthBefore - 1, lengthAfter);

    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(erc4626StrategyVault)));
    vm.prank(strategist);
    sizeMetaVault.rebalance(cashStrategyVault, erc4626StrategyVault, cashAssets, 0);
  }

  function test_SizeMetaVault_rebalance_strategyFrom_and_strategyTo_same_must_revert() public {
    uint256 assetsToTransfer = 100e6;
    _deposit(alice, sizeMetaVault, assetsToTransfer);

    vm.prank(strategist);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cashStrategyVault)));
    sizeMetaVault.rebalance(cashStrategyVault, cashStrategyVault, assetsToTransfer, 0);
  }

  function test_SizeMetaVault_reorderStrategies() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = aaveStrategyVault;
    strategies[1] = erc4626StrategyVault;
    strategies[2] = cashStrategyVault;

    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    assertEq(address(sizeMetaVault.strategies(0)), address(strategies[0]));
    assertEq(address(sizeMetaVault.strategies(1)), address(strategies[1]));
    assertEq(address(sizeMetaVault.strategies(2)), address(strategies[2]));

    assertTrue(sizeMetaVault.isStrategy(strategies[0]));
    assertTrue(sizeMetaVault.isStrategy(strategies[1]));
    assertTrue(sizeMetaVault.isStrategy(strategies[2]));
  }

  function test_SizeMetaVault_addStrategy() public {
    address oneStrategy = address(cryticCashStrategyVault);

    uint256 lengthBefore = sizeMetaVault.strategiesCount();

    vm.prank(manager);
    sizeMetaVault.addStrategy(IVault(oneStrategy));

    uint256 lengthAfter = sizeMetaVault.strategiesCount();
    uint256 indexLastStrategy = lengthAfter - 1;

    address lastStrategyAdded = address(sizeMetaVault.strategies(indexLastStrategy));

    vm.assertEq(lengthAfter, lengthBefore + 1);
    vm.assertEq(oneStrategy, lastStrategyAdded);
  }

  function test_SizeMetaVault_addStrategy_invalid_asset_must_revert() public {
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cashStrategyVaultWETH)));
    sizeMetaVault.addStrategy(cashStrategyVaultWETH);
  }

  function test_SizeMetaVault_addStrategy_invalid_auth_must_revert() public {
    address invalidAuth = address(0xDEAD);

    vm.mockCall(address(cryticCashStrategyVault), abi.encodeWithSelector(IVault.auth.selector), abi.encode(invalidAuth));

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cryticCashStrategyVault)));
    sizeMetaVault.addStrategy(cryticCashStrategyVault);
  }

  function test_SizeMetaVault_addStrategy_address_zero_must_revert() public {
    uint256 lengthBefore = sizeMetaVault.strategiesCount();

    vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
    vm.prank(manager);
    sizeMetaVault.addStrategy(IVault(address(0)));

    uint256 lengthAfter = sizeMetaVault.strategiesCount();

    assertEq(lengthBefore, lengthAfter);
  }

  function test_SizeMetaVault_addStrategy_removeStrategy() public {
    vm.prank(manager);
    sizeMetaVault.addStrategy(cryticCashStrategyVault);

    vm.prank(guardian);
    sizeMetaVault.removeStrategy(erc4626StrategyVault, cashStrategyVault, type(uint256).max, 0);
  }

  function test_SizeMetaVault_removeStrategy() public {
    _deposit(alice, sizeMetaVault, 100e6);

    uint256 length = sizeMetaVault.strategiesCount();
    IVault[] memory currentStrategies = new IVault[](length);
    currentStrategies = sizeMetaVault.strategies();

    for (uint256 i = 0; i < currentStrategies.length; i++) {
      uint256 strategyAssets = currentStrategies[i].totalAssets();
      vm.prank(strategist);
      sizeMetaVault.rebalance(currentStrategies[i], currentStrategies[(i + 1) % length], strategyAssets / 2, 0);
    }

    vm.prank(manager);
    sizeMetaVault.addStrategy(cryticCashStrategyVault);

    for (uint256 i = 0; i < currentStrategies.length; i++) {
      vm.prank(guardian);
      sizeMetaVault.removeStrategy(currentStrategies[i], cryticCashStrategyVault, type(uint256).max, 0);
    }

    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cryticCashStrategyVault)));
    vm.prank(guardian);
    sizeMetaVault.removeStrategy(cryticCashStrategyVault, cryticCashStrategyVault, type(uint256).max, 0);

    assertGt(cryticCashStrategyVault.totalAssets(), 0);
  }

  function test_SizeMetaVault_removeStrategy_paused_should_revert() public {}

  function test_SizeMetaVault_removeStrategy_invalid_strategy_must_revert() public {
    vm.prank(admin);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.InvalidStrategy.selector, address(cryticCashStrategyVault)));
    sizeMetaVault.removeStrategy(cryticCashStrategyVault, cashStrategyVault, type(uint256).max, 0);
  }

  function test_SizeMetaVault_deposit_withdraw() public {
    uint256 initialTotalAssets = sizeMetaVault.totalAssets();

    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(sizeMetaVault), depositAmount);

    vm.prank(alice);
    sizeMetaVault.deposit(depositAmount, alice);

    vm.prank(alice);
    sizeMetaVault.withdraw(depositAmount - 1, alice, alice);

    assertEq(sizeMetaVault.balanceOf(alice), 1);
    assertEq(sizeMetaVault.totalAssets(), initialTotalAssets + 1);
    assertEq(erc20Asset.balanceOf(alice), depositAmount - 1);
  }

  function test_SizeMetaVault_deposit_deposit_withdraw() public {
    uint256 initialTotalAssets = sizeMetaVault.totalAssets();

    uint256 firstDepositAmount = 100e6;
    uint256 secondDepositAmount = 50e6;
    _mint(erc20Asset, alice, firstDepositAmount + secondDepositAmount);
    _approve(alice, erc20Asset, address(sizeMetaVault), firstDepositAmount + secondDepositAmount);

    vm.startPrank(alice);
    sizeMetaVault.deposit(firstDepositAmount, alice);
    sizeMetaVault.deposit(secondDepositAmount, alice);
    vm.stopPrank();

    vm.startPrank(alice);
    sizeMetaVault.withdraw(firstDepositAmount, alice, alice);
    sizeMetaVault.withdraw(secondDepositAmount - 1, alice, alice);
    vm.stopPrank();

    assertEq(sizeMetaVault.balanceOf(alice), 1);
    assertEq(sizeMetaVault.totalAssets(), initialTotalAssets + 1);
    assertEq(erc20Asset.balanceOf(alice), firstDepositAmount + secondDepositAmount - 1);
  }

  function test_SizeMetaVault_deposit_redeem() public {
    uint256 initialTotalAssets = sizeMetaVault.totalAssets();

    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(sizeMetaVault), depositAmount);

    vm.prank(alice);
    sizeMetaVault.deposit(depositAmount, alice);

    uint256 shares = sizeMetaVault.balanceOf(alice);

    vm.prank(alice);
    sizeMetaVault.redeem(shares, alice, alice);

    assertEq(sizeMetaVault.balanceOf(alice), 0);
    assertEq(sizeMetaVault.totalAssets(), initialTotalAssets);
    assertEq(erc20Asset.balanceOf(alice), depositAmount);
  }

  ////////////////////////////////////////////
  // Customized Vault for ERC4626StrategyVault was used to hit specific edge cases
  ///////////////////////////////////////////

  function deployNewERC4626StrategyVault(VaultType vaultType) public returns (ERC4626StrategyVault newERC4626StrategyVault) {
    ERC4626StrategyVaultScript deployer = new ERC4626StrategyVaultScript();

    _mint(erc20Asset, address(deployer), FIRST_DEPOSIT_AMOUNT);

    if (vaultType == VaultType.REVERT_ON_DEPOSIT) {
      vault_revertDeposit = new VaultMockRevertOnDeposit(bob, erc20Asset, "VaultMockRevertOnDeposit", "VMO");
      vm.label(address(vault_revertDeposit), "VaultMockRevertOnDeposit");
      newERC4626StrategyVault = deployer.deploy(auth, FIRST_DEPOSIT_AMOUNT, vault_revertDeposit);
    } else if (vaultType == VaultType.REVERT_ON_WITHDRAW) {
      vault_revertWithdraw = new VaultMockRevertOnWithdraw(bob, erc20Asset, "VaultMockRevertOnWithdraw", "VMO");
      vm.label(address(vault_revertWithdraw), "VaultMockRevertOnWithdraw");
      newERC4626StrategyVault = deployer.deploy(auth, FIRST_DEPOSIT_AMOUNT, vault_revertWithdraw);
    } else if (vaultType == VaultType.ASSET_FEE_ON_DEPOSIT) {
      vault_assetFeeOnDeposit = new VaultMockAssetFeeOnDeposit(bob, erc20Asset, "VaultMockAssetFeeOnDeposit", "VMO");
      vm.label(address(vault_assetFeeOnDeposit), "VaultMockAssetFeeOnDeposit");
      newERC4626StrategyVault = deployer.deploy(auth, FIRST_DEPOSIT_AMOUNT, vault_assetFeeOnDeposit);
    } else if (vaultType == VaultType.ASSET_FEE_ON_WITHDRAW) {
      vault_assetFeeOnWithdraw = new VaultMockAssetFeeOnWithdraw(bob, erc20Asset, "VaultMockAssetFeeOnWithdraw", "VMO");
      vm.label(address(vault_assetFeeOnWithdraw), "VaultMockAssetFeeOnWithdraw");
      newERC4626StrategyVault = deployer.deploy(auth, FIRST_DEPOSIT_AMOUNT, vault_assetFeeOnWithdraw);
    } else {
      revert("Invalid vault type");
    }
    vm.label(address(newERC4626StrategyVault), "NewERC4626StrategyVault");

    IVault[] memory oldStrategies = sizeMetaVault.strategies();
    IVault[] memory newStrategies = new IVault[](1);
    newStrategies[0] = newERC4626StrategyVault;

    vm.prank(manager);
    sizeMetaVault.addStrategy(newERC4626StrategyVault);

    for (uint256 i = 0; i < oldStrategies.length; i++) {
      vm.prank(guardian);
      sizeMetaVault.removeStrategy(oldStrategies[i], newERC4626StrategyVault, type(uint256).max, 0);
    }

    return newERC4626StrategyVault;
  }

  function test_SizeMetaVault_deposit_revert_if_all_assets_cannot_be_deposited() public {
    deployNewERC4626StrategyVault(VaultType.REVERT_ON_DEPOSIT);

    // now, only on strategy with customized maxDeposit that is not type(uint256).max

    _mint(erc20Asset, alice, type(uint256).max);
    _approve(alice, erc20Asset, address(sizeMetaVault), type(uint256).max);

    vm.prank(bob);
    vault_revertDeposit.setRevertOnDeposit(true);

    uint256 shares = sizeMetaVault.previewDeposit(type(uint32).max);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.CannotDepositToStrategies.selector, type(uint32).max, shares, type(uint32).max));
    sizeMetaVault.deposit(type(uint32).max, alice);
  }

  function test_SizeMetaVault_withdraw_revert_if_all_assets_cannot_be_withdrawn() public {
    deployNewERC4626StrategyVault(VaultType.REVERT_ON_WITHDRAW);

    uint256 amount = 100e6;

    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(sizeMetaVault), amount);

    vm.prank(alice);
    sizeMetaVault.deposit(amount, alice);

    uint256 withdrawableAssets = sizeMetaVault.maxWithdraw(alice);
    uint256 shares = sizeMetaVault.previewWithdraw(withdrawableAssets);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.CannotWithdrawFromStrategies.selector, withdrawableAssets, shares, withdrawableAssets));
    sizeMetaVault.withdraw(withdrawableAssets, alice, alice);
  }

  function test_SizeMetaVault_deposit_reverts_if_asset_fee_on_deposit() public {
    try this.deployNewERC4626StrategyVault(VaultType.ASSET_FEE_ON_DEPOSIT) {
      assertTrue(false, "Should revert");
    } catch (bytes memory err) {
      assertEq(bytes4(err), SizeMetaVault.TransferredAmountLessThanMin.selector);
    }
  }

  function test_SizeMetaVault_withdraw_reverts_if_asset_fee_on_withdraw() public {
    IVault newStrategy = deployNewERC4626StrategyVault(VaultType.ASSET_FEE_ON_WITHDRAW);

    uint256 depositAmount = 1000e6;

    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(sizeMetaVault), depositAmount);

    vm.prank(alice);
    sizeMetaVault.deposit(depositAmount, alice);

    uint256 withdrawAmount = 100e6;
    uint256 withdrawFee = vault_assetFeeOnWithdraw.ASSET_FEE_PERCENT() * withdrawAmount / vault_assetFeeOnWithdraw.PERCENT();
    uint256 shares = sizeMetaVault.previewWithdraw(withdrawAmount);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.CannotWithdrawFromStrategies.selector, withdrawAmount, shares, withdrawAmount));
    sizeMetaVault.withdraw(withdrawAmount, alice, alice);

    vm.prank(manager);
    sizeMetaVault.addStrategy(cashStrategyVault);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(newStrategy), withdrawAmount - withdrawFee, withdrawAmount));
    sizeMetaVault.removeStrategy(newStrategy, cashStrategyVault, withdrawAmount, 0.01e18);

    IVault[] memory strategies = new IVault[](2);
    strategies[0] = cashStrategyVault;
    strategies[1] = newStrategy;
    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    uint256 dust = 1;
    _deposit(guardian, sizeMetaVault, dust);

    vm.prank(guardian);
    sizeMetaVault.removeStrategy(newStrategy, cashStrategyVault, 0, 0);

    assertEq(sizeMetaVault.balanceOf(alice), depositAmount);
    assertEq(sizeMetaVault.convertToAssets(sizeMetaVault.balanceOf(alice)), dust);
  }

  function test_SizeMetaVault_addStrategy_max_strategies_exceeded() public {
    ERC4626StrategyVaultScript deployer = new ERC4626StrategyVaultScript();
    uint256 maxStrategies = sizeMetaVault.MAX_STRATEGIES();
    uint256 currentStrategiesCount = sizeMetaVault.strategiesCount();
    uint256 length = maxStrategies * 2;
    for (uint256 i = currentStrategiesCount; i <= length; i++) {
      ERC4626Mock vault = new ERC4626Mock(address(erc20Asset));
      _mint(erc20Asset, address(deployer), FIRST_DEPOSIT_AMOUNT);
      IVault strategy = deployer.deploy(auth, FIRST_DEPOSIT_AMOUNT, vault);
      if (i >= maxStrategies) vm.expectRevert(abi.encodeWithSelector(SizeMetaVault.MaxStrategiesExceeded.selector, maxStrategies + 1, maxStrategies));
      vm.prank(manager);
      sizeMetaVault.addStrategy(strategy);
    }
  }

  function test_SizeMetaVault_maxWithdraw_cannot_be_used_to_steal_assets() public {
    _deposit(alice, sizeMetaVault, 100e6);
    _deposit(bob, sizeMetaVault, 200e6);

    uint256 maxWithdraw = sizeMetaVault.maxWithdraw(alice);

    vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector, alice, 150e6, maxWithdraw));
    _withdraw(alice, sizeMetaVault, 150e6);
  }

  function test_SizeMetaVault_deposit_continues_trying_from_other_strategies() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = erc4626StrategyVault;
    strategies[1] = cashStrategyVault;
    strategies[2] = aaveStrategyVault;

    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    IERC4626 vault = erc4626StrategyVault.vault();
    vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.maxDeposit.selector, address(erc4626StrategyVault)), abi.encode(0));

    _deposit(alice, sizeMetaVault, 100e6);

    assertEq(sizeMetaVault.balanceOf(alice), 100e6);
  }

  function test_SizeMetaVault_withdraw_continues_trying_from_other_strategies() public {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = cashStrategyVault;
    strategies[1] = erc4626StrategyVault;
    strategies[2] = aaveStrategyVault;

    vm.prank(strategist);
    sizeMetaVault.reorderStrategies(strategies);

    _deposit(alice, sizeMetaVault, 100e6);
    _deposit(bob, sizeMetaVault, 200e6);

    vm.prank(strategist);
    sizeMetaVault.rebalance(cashStrategyVault, aaveStrategyVault, 150e6, 0);

    IERC4626 vault = erc4626StrategyVault.vault();
    vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.maxWithdraw.selector, address(erc4626StrategyVault)), abi.encode(0));

    vm.prank(alice);
    sizeMetaVault.withdraw(100e6, alice, alice);
    assertEq(erc20Asset.balanceOf(alice), 100e6);
  }

  function test_SizeMetaVault_strategy_can_be_a_SizeMetaVault() public {
    _log(sizeMetaVault);
    uint256 amount = 100e6;
    _deposit(alice, sizeMetaVault, amount);

    uint256 totalAssetsBefore = sizeMetaVault.totalAssets();

    vm.prank(manager);
    sizeMetaVault.addStrategy(cryticSizeMetaVault);

    _log(sizeMetaVault);

    IVault[] memory strategies = sizeMetaVault.strategies();

    vm.prank(strategist);
    sizeMetaVault.rebalance(strategies[0], cryticSizeMetaVault, amount, 0);

    uint256 totalAssetsAfter = sizeMetaVault.totalAssets();

    assertEq(totalAssetsAfter, totalAssetsBefore);
  }
}
