// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Vm } from '@std/Vm.sol';

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { IERC4626 } from '@oz/interfaces/IERC4626.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ERC20 } from '@oz/token/ERC20/ERC20.sol';

import { AssetManager } from '../../../src/hub/core/AssetManager.sol';
import { AssetManagerStorageV1 } from '../../../src/hub/core/AssetManagerStorageV1.sol';
import { HubAsset } from '../../../src/hub/core/HubAsset.sol';
import { ReclaimQueue } from '../../../src/hub/ReclaimQueue.sol';
import { Treasury } from '../../../src/hub/reward/Treasury.sol';
import { VLFVaultBasic } from '../../../src/hub/vlf/VLFVaultBasic.sol';
import { IAssetManager, IAssetManagerStorageV1 } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { IAssetManagerEntrypoint } from '../../../src/interfaces/hub/core/IAssetManagerEntrypoint.sol';
import { IHubAsset } from '../../../src/interfaces/hub/core/IHubAsset.sol';
import { IReclaimQueue } from '../../../src/interfaces/hub/IReclaimQueue.sol';
import { ITreasury } from '../../../src/interfaces/hub/reward/ITreasury.sol';
import { IVLFVault } from '../../../src/interfaces/hub/vlf/IVLFVault.sol';
import { IVLFVaultFactory } from '../../../src/interfaces/hub/vlf/IVLFVaultFactory.sol';
import { IBeaconBase } from '../../../src/interfaces/lib/proxy/IBeaconBase.sol';
import { StdError } from '../../../src/lib/StdError.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract AssetManagerErrors {
  function _errTreasuryNotSet() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__TreasuryNotSet.selector);
  }

  function _errBranchAssetPairNotExist(uint256 chainId, address branchAsset) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__BranchAssetPairNotExist.selector, chainId, branchAsset
    );
  }

  function _errHubAssetPairNotExist(address hubAsset) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__HubAssetPairNotExist.selector, hubAsset);
  }

  function _errHubAssetFactoryNotSet() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__HubAssetFactoryNotSet.selector);
  }

  function _errVLFVaultFactoryNotSet() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__VLFVaultFactoryNotSet.selector);
  }

  function _errVLFNotInitialized(uint256 chainId, address vlfVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__VLFNotInitialized.selector, chainId, vlfVault
    );
  }

  function _errVLFAlreadyInitialized(uint256 chainId, address vlfVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__VLFAlreadyInitialized.selector, chainId, vlfVault
    );
  }

  function _errBranchAvailableLiquidityInsufficient(
    uint256 chainId,
    address hubAsset,
    uint256 available,
    uint256 amount
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__BranchAvailableLiquidityInsufficient.selector,
      chainId,
      hubAsset,
      available,
      amount
    );
  }

  function _errInvalidHubAsset(address hubAsset) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__InvalidHubAsset.selector, hubAsset);
  }

  function _errInvalidVLFVault(address vlfVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__InvalidVLFVault.selector, vlfVault);
  }

  function _errVLFNothingToVLFReserve(address vlfVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManager.IAssetManager__NothingToVLFReserve.selector, vlfVault);
  }

  function _errVLFLiquidityInsufficient(address vlfVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManager.IAssetManager__VLFLiquidityInsufficient.selector, vlfVault);
  }

  function _errBranchLiquidityThresholdNotSatisfied(
    uint256 chainId,
    address hubAsset,
    uint256 threshold,
    uint256 withdrawAmount
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__BranchLiquidityThresholdNotSatisfied.selector,
      chainId,
      hubAsset,
      threshold,
      withdrawAmount
    );
  }
}

contract AssetManagerTest is AssetManagerErrors, Toolkit {
  MockContract reclaimQueue;
  MockContract entrypoint;
  MockContract treasury;
  MockContract vlfVault;
  MockContract vlfFactory;
  MockContract hubAsset;
  MockContract hubAssetFactory;

  AssetManager assetManager;

  address owner = makeAddr('owner');
  address liquidityManager = makeAddr('liquidityManager');
  address user1 = makeAddr('user1');
  address immutable mitosis = makeAddr('mitosis');

  uint48 branchChainId1 = 10;
  uint48 branchChainId2 = 20;
  address branchAsset1 = makeAddr('branchAsset1');
  address branchAsset2 = makeAddr('branchAsset2');
  address branchRewardTokenAddress = makeAddr('branchRewardTokenAddress');
  address strategist = makeAddr('strategist');

  function setUp() public {
    reclaimQueue = new MockContract();
    reclaimQueue.setCall(IReclaimQueue.sync.selector);

    entrypoint = new MockContract();
    entrypoint.setCall(IAssetManagerEntrypoint.withdraw.selector);
    entrypoint.setCall(IAssetManagerEntrypoint.allocateVLF.selector);
    entrypoint.setCall(IAssetManagerEntrypoint.initializeAsset.selector);
    entrypoint.setCall(IAssetManagerEntrypoint.initializeVLF.selector);

    treasury = new MockContract();
    treasury.setCall(ITreasury.storeRewards.selector);

    vlfVault = new MockContract();
    vlfVault.setCall(IERC4626.deposit.selector);
    vlfVault.setCall(IVLFVault.depositFromChainId.selector);
    vlfFactory = new MockContract();

    hubAsset = new MockContract();
    // hubAsset.setCall(IHubAsset.decimals.selector);
    hubAsset.setRet(abi.encodeCall(IERC20Metadata.decimals, ()), false, abi.encode(18));
    hubAsset.setCall(IHubAsset.mint.selector);
    hubAsset.setCall(IHubAsset.burn.selector);
    hubAsset.setCall(IERC20.approve.selector);
    hubAsset.setCall(IERC20.transfer.selector);
    hubAsset.setCall(IERC20.transferFrom.selector);

    hubAssetFactory = new MockContract();

    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));

    assetManager = AssetManager(
      payable(
        new ERC1967Proxy(
          address(new AssetManager()), abi.encodeCall(AssetManager.initialize, (owner, address(treasury)))
        )
      )
    );

    vm.startPrank(owner);
    assetManager.grantRole(assetManager.LIQUIDITY_MANAGER_ROLE(), liquidityManager);
    assetManager.setReclaimQueue(address(reclaimQueue));
    assetManager.setEntrypoint(address(entrypoint));
    vm.stopPrank();
  }

  function test_deposit() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.Deposited(branchChainId1, address(hubAsset), user1, 100 ether);
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (user1, 100 ether)));
  }

  function test_deposit_Unauthorized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);
  }

  function test_deposit_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchAsset1));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);
  }

  function test_depositWithSupplyVLF() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vm.prank(owner);
    assetManager.initializeVLF(branchChainId1, address(vlfVault));

    // vault.asset != hubAsset

    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(branchAsset1)));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyVLF(branchChainId1, address(hubAsset), user1, address(vlfVault), 100 ether, 0);
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (user1, 100 ether)));

    // maxDepositFromChainId > amount

    hubAsset.setRet(abi.encodeCall(IERC20.approve, (address(vlfVault), 100 ether)), false, abi.encode(true));
    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.maxDepositFromChainId, (user1, branchChainId1)), false, abi.encode(101 ether)
    );
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.depositFromChainId, (100 ether, user1, branchChainId1)), false, abi.encode(100 ether)
    );

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyVLF(
      branchChainId1, address(hubAsset), user1, address(vlfVault), 100 ether, 100 ether
    );
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.approve, (address(vlfVault), 100 ether)));
    vlfVault.assertLastCall(abi.encodeCall(IVLFVault.depositFromChainId, (100 ether, user1, branchChainId1)));

    // maxDepositFromChainId < amount

    hubAsset.setRet(abi.encodeCall(IERC20.approve, (address(vlfVault), 99 ether)), false, abi.encode(true));
    hubAsset.setRet(abi.encodeCall(IERC20.transfer, (user1, 1 ether)), false, abi.encode(true));
    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.maxDepositFromChainId, (user1, branchChainId1)), false, abi.encode(99 ether)
    );
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.depositFromChainId, (99 ether, user1, branchChainId1)), false, abi.encode(99 ether)
    );

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyVLF(
      branchChainId1, address(hubAsset), user1, address(vlfVault), 100 ether, 99 ether
    );
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.approve, (address(vlfVault), 99 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.transfer, (address(user1), 1 ether)));
    vlfVault.assertLastCall(abi.encodeCall(IVLFVault.depositFromChainId, (99 ether, user1, branchChainId1)));
  }

  function test_depositWithSupplyVLF_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);
  }

  /// @dev No occurrence case until methods like unsetAssetPair are added.
  function test_depositWithSupplyVLF_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchAsset1));
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);
  }

  function test_depositWithSupplyVLF_VLFVaultNotInitialized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vm.prank(address(entrypoint));
    vm.expectRevert(_errVLFNotInitialized(branchChainId1, address(vlfVault)));
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);
  }

  function test_withdraw() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(user1);
    vm.expectEmit();
    emit IAssetManager.Withdrawn(branchChainId1, address(hubAsset), user1, 100 ether, 100 ether);
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.burn, (user1, 100 ether)));
    entrypoint.assertLastCall(
      abi.encodeCall(
        IAssetManagerEntrypoint.withdraw, //
        (branchChainId1, branchAsset1, user1, 100 ether)
      )
    );
  }

  /// @dev No occurrence case until methods like unsetAssetPair are added.
  function test_withdraw_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, address(0)));
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 100 ether);
  }

  function test_withdraw_ToZeroAddress() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(user1);
    vm.expectRevert(_errZeroToAddress());
    assetManager.withdraw(branchChainId1, address(hubAsset), address(0), 100 ether);
  }

  function test_withdraw_ZeroAmount() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(user1);
    vm.expectRevert(_errZeroAmount());
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 0);
  }

  function test_withdraw_BranchAvailableLiquidityInsufficient() public {
    test_allocateVLF();

    vm.prank(user1);
    vm.expectRevert(_errBranchAvailableLiquidityInsufficient(branchChainId1, address(hubAsset), 200 ether, 201 ether));
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 201 ether);
  }

  function test_withdraw_BranchLiquidityThresholdNotSatisfied() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(liquidityManager);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 80 ether);

    vm.prank(user1);
    vm.expectRevert(_errBranchLiquidityThresholdNotSatisfied(branchChainId1, address(hubAsset), 80 ether, 21 ether));
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 21 ether);
  }

  function test_allocateVLF() public {
    test_depositWithSupplyVLF();

    vm.prank(owner);
    assetManager.setStrategist(address(vlfVault), strategist);

    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(200 ether));

    vm.prank(strategist);
    vm.expectEmit();
    emit IAssetManager.VLFAllocated(strategist, branchChainId1, address(vlfVault), 100 ether, 100 ether);
    assetManager.allocateVLF(branchChainId1, address(vlfVault), 100 ether);
  }

  function test_allocateVLF_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.allocateVLF(branchChainId1, address(vlfVault), 100 ether);
  }

  function test_allocateVLF_VLFVaultNotInitialized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vm.prank(owner);
    assetManager.setStrategist(address(vlfVault), strategist);

    vm.prank(strategist);
    vm.expectRevert(_errVLFNotInitialized(branchChainId1, address(vlfVault)));
    assetManager.allocateVLF(branchChainId1, address(vlfVault), 100 ether);
  }

  function test_allocateVLF_VLFInsufficient() public {
    test_depositWithSupplyVLF();

    vm.prank(owner);
    assetManager.setStrategist(address(vlfVault), strategist);

    // mint 100 of hubAsset to user1
    vlfVault.setRet(abi.encodeCall(IERC4626.maxDeposit, (user1)), false, abi.encode(100 ether));
    vm.prank(address(entrypoint));
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);

    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(100 ether));

    vm.prank(strategist);
    vm.expectRevert(_errVLFLiquidityInsufficient(address(vlfVault)));
    assetManager.allocateVLF(branchChainId1, address(vlfVault), 101 ether);
  }

  function test_allocateVLF_BranchAvailableLiquidityInsufficient() public {
    test_depositWithSupplyVLF();

    vm.startPrank(owner);
    assetManager.setAssetPair(address(hubAsset), branchChainId2, branchAsset2, 18);
    assetManager.initializeVLF(branchChainId2, address(vlfVault));
    assetManager.setStrategist(address(vlfVault), strategist);
    vm.stopPrank();

    // mint 100 of hubAsset to user1 for each branch chains
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.maxDepositFromChainId, (user1, branchChainId1)), false, abi.encode(100 ether)
    );
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.maxDepositFromChainId, (user1, branchChainId2)), false, abi.encode(100 ether)
    );
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.depositFromChainId, (100 ether, user1, branchChainId1)), false, abi.encode(100 ether)
    );
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.depositFromChainId, (100 ether, user1, branchChainId2)), false, abi.encode(100 ether)
    );
    vm.startPrank(address(entrypoint));
    assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, user1, address(vlfVault), 100 ether);
    assetManager.depositWithSupplyVLF(branchChainId2, branchAsset2, user1, address(vlfVault), 100 ether);
    vm.stopPrank();

    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(500 ether));

    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId1), 400 ether);
    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId2), 100 ether);
    assertEq(assetManager.vlfIdle(address(vlfVault)), 500 ether);
    assertEq(assetManager.vlfAlloc(address(vlfVault)), 0 ether);

    vm.startPrank(strategist);
    assetManager.allocateVLF(branchChainId1, address(vlfVault), 30 ether);
    assetManager.allocateVLF(branchChainId2, address(vlfVault), 50 ether);
    vm.stopPrank();

    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId1), 370 ether);
    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId2), 50 ether);
    assertEq(assetManager.vlfIdle(address(vlfVault)), 420 ether);
    assertEq(assetManager.vlfAlloc(address(vlfVault)), 80 ether);

    vm.prank(strategist);
    vm.expectRevert(_errBranchAvailableLiquidityInsufficient(branchChainId1, address(hubAsset), 370 ether, 371 ether));
    assetManager.allocateVLF(branchChainId1, address(vlfVault), 371 ether);

    vm.prank(strategist);
    vm.expectRevert(_errBranchAvailableLiquidityInsufficient(branchChainId2, address(hubAsset), 50 ether, 51 ether));
    assetManager.allocateVLF(branchChainId2, address(vlfVault), 51 ether);
  }

  function test_deallocateVLF() public {
    test_allocateVLF(); // load 200 hubAssets
    assertEq(assetManager.vlfIdle(address(vlfVault)), 100 ether);
    assertEq(assetManager.vlfAlloc(address(vlfVault)), 100 ether);

    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(100 ether));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.VLFDeallocated(branchChainId1, address(vlfVault), 100 ether);
    assetManager.deallocateVLF(branchChainId1, address(vlfVault), 100 ether);

    assertEq(assetManager.vlfIdle(address(vlfVault)), 100 ether);
    assertEq(assetManager.vlfAlloc(address(vlfVault)), 0);
  }

  function test_deallocateVLF_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.deallocateVLF(branchChainId1, address(vlfVault), 100 ether);
  }

  function test_reserveVLF() public {
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(200 ether));
    reclaimQueue.setRet(
      abi.encodeCall(IReclaimQueue.previewSync, (address(vlfVault), 100)), false, abi.encode(0, 100 ether)
    );
    reclaimQueue.setRet(
      abi.encodeCall(IReclaimQueue.sync, (strategist, address(vlfVault), 100)), false, abi.encode(100, 100 ether)
    );

    vm.prank(owner);
    assetManager.setStrategist(address(vlfVault), strategist);

    vm.prank(strategist);
    vm.expectEmit();
    emit IAssetManager.VLFReserved(strategist, address(vlfVault), 100, 100, 100 ether);
    assetManager.reserveVLF(address(vlfVault), 100);

    reclaimQueue.assertLastCall(abi.encodeCall(IReclaimQueue.sync, (strategist, address(vlfVault), 100)));
  }

  function test_reserveVLF_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.reserveVLF(address(vlfVault), 10);
  }

  function test_reserveVLF_VLFNothingToReserve() public {
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(200 ether));
    reclaimQueue.setRet(abi.encodeCall(IReclaimQueue.previewSync, (address(vlfVault), 100)), false, abi.encode(0, 0));

    vm.prank(owner);
    assetManager.setStrategist(address(vlfVault), strategist);

    vm.prank(strategist);
    vm.expectRevert(_errVLFNothingToVLFReserve(address(vlfVault)));
    assetManager.reserveVLF(address(vlfVault), 100);
  }

  function test_reserveVLF_VLFVaultInsufficient() public {
    test_initializeVLF();

    vm.prank(owner);
    assetManager.setStrategist(address(vlfVault), strategist);

    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(100 ether));
    reclaimQueue.setRet(
      abi.encodeCall(IReclaimQueue.previewSync, (address(vlfVault), 100)), false, abi.encode(0, 200 ether)
    );

    vm.prank(strategist);
    vm.expectRevert(_errVLFLiquidityInsufficient(address(vlfVault)));
    assetManager.reserveVLF(address(vlfVault), 100);
  }

  function test_settleVLFYield() public {
    test_allocateVLF();

    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.VLFRewardSettled(branchChainId1, address(vlfVault), address(hubAsset), 100 ether);
    assetManager.settleVLFYield(branchChainId1, address(vlfVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(vlfVault), 100 ether)));
  }

  function test_settleVLFYield_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.settleVLFYield(branchChainId1, address(vlfVault), 100 ether);
  }

  function test_settleVLFLoss() public {
    test_allocateVLF();

    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.VLFLossSettled(branchChainId1, address(vlfVault), address(hubAsset), 100 ether);
    assetManager.settleVLFLoss(branchChainId1, address(vlfVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.burn, (address(vlfVault), 100 ether)));
  }

  function test_settleVLFLoss_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.settleVLFLoss(branchChainId1, address(vlfVault), 10 ether);
  }

  function test_settleVLFExtraRewards() public {
    MockContract rewardToken = new MockContract();
    rewardToken.setCall(IERC20.approve.selector);
    rewardToken.setCall(IHubAsset.mint.selector);
    rewardToken.setRet(abi.encodeCall(IERC20Metadata.decimals, ()), false, abi.encode(18));
    rewardToken.setRet(abi.encodeCall(IERC20.approve, (address(treasury), 100 ether)), false, abi.encode(true));

    _setAssetPair(address(rewardToken), branchChainId1, branchRewardTokenAddress, 18);

    vm.prank(owner);
    assetManager.setTreasury(address(treasury));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.VLFRewardSettled(branchChainId1, address(vlfVault), address(rewardToken), 100 ether);
    assetManager.settleVLFExtraRewards(branchChainId1, address(vlfVault), branchRewardTokenAddress, 100 ether);

    rewardToken.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    rewardToken.assertLastCall(abi.encodeCall(IERC20.approve, (address(treasury), 100 ether)));

    treasury.assertLastCall(
      abi.encodeCall(ITreasury.storeRewards, (address(vlfVault), address(rewardToken), 100 ether))
    );
  }

  function test_settleVLFExtraRewards_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.settleVLFExtraRewards(branchChainId1, address(vlfVault), branchRewardTokenAddress, 100 ether);
  }

  function test_settleVLFExtraRewards_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchRewardTokenAddress));
    assetManager.settleVLFExtraRewards(branchChainId1, address(vlfVault), branchRewardTokenAddress, 100 ether);
  }

  function test_initializeAsset() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManager.AssetInitialized(address(hubAsset), branchChainId1, branchAsset1, 18);
    assetManager.initializeAsset(branchChainId1, address(hubAsset));

    entrypoint.assertLastCall(abi.encodeCall(IAssetManagerEntrypoint.initializeAsset, (branchChainId1, branchAsset1)));

    assertEq(assetManager.branchAsset(address(hubAsset), branchChainId1), branchAsset1);
  }

  function test_initializeAsset_Unauthorized() public {
    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.DEFAULT_ADMIN_ROLE()));
    vm.prank(user1);
    assetManager.initializeAsset(branchChainId1, address(hubAsset));
  }

  function test_initializeAsset_InvalidParameter() public {
    vm.startPrank(owner);

    vm.expectRevert(_errInvalidParameter('hubAsset'));
    assetManager.initializeAsset(branchChainId1, address(0));

    vm.expectRevert(_errInvalidParameter('hubAsset'));
    assetManager.initializeAsset(branchChainId1, user1);

    vm.stopPrank();
  }

  function test_initializeAsset_BranchAssetPairNotExist() public {
    vm.prank(owner);
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, address(0)));
    assetManager.initializeAsset(branchChainId1, address(hubAsset));
  }

  function test_diff_branch_asset_and_hub_asset() public {
    HubAsset hub = HubAsset(
      _proxy(
        address(new HubAsset()), abi.encodeCall(HubAsset.initialize, (owner, address(assetManager), 'Token', 'TKN', 18))
      )
    );

    // HubAsset decimals: 18
    _setAssetPair(address(hub), branchChainId1, branchAsset1, 18);
    _setAssetPair(address(hub), branchChainId2, branchAsset1, 8);

    vm.startPrank(address(entrypoint));

    {
      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.Deposited(branchChainId1, address(hub), address(1), 5 * 10 ** 18);
      assetManager.deposit(branchChainId1, branchAsset1, address(1), 5 * 10 ** 18);

      vm.expectEmit();
      emit IAssetManager.Deposited(branchChainId1, address(hub), address(1), 1_000_000_000 * 10 ** 18);
      assetManager.deposit(branchChainId1, branchAsset1, address(1), 1_000_000_000 * 10 ** 18);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.Deposited(branchChainId2, address(hub), address(1), 15 * 10 ** 18);
      assetManager.deposit(branchChainId2, branchAsset1, address(1), 15 * 10 ** 8);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.Deposited(branchChainId2, address(hub), address(1), 100_001_001 * 10 ** (18 - 8));
      assetManager.deposit(branchChainId2, branchAsset1, address(1), 100_001_001);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.Deposited(branchChainId2, address(hub), address(1), 1 * 10 ** (18 - 8));
      assetManager.deposit(branchChainId2, branchAsset1, address(1), 1);

      vm.expectEmit();
      emit IAssetManager.Deposited(branchChainId2, address(hub), address(1), 1_000_000_000 * 10 ** 18);
      assetManager.deposit(branchChainId2, branchAsset1, address(1), 1_000_000_000 * 10 ** 8);

      vm.stopPrank();
    }

    {
      vm.startPrank(address(1));

      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.Withdrawn(branchChainId1, address(hub), address(1), 1 * 10 ** 18, 1 * 10 ** 18);
      assetManager.withdraw(branchChainId1, address(hub), address(1), 1 * 10 ** 18);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.Withdrawn(branchChainId2, address(hub), address(1), 1 * 10 ** 18, 1 * 10 ** 8);
      assetManager.withdraw(branchChainId2, address(hub), address(1), 1 * 10 ** 18);

      vm.expectEmit();
      emit IAssetManager.Withdrawn(branchChainId2, address(hub), address(1), 1_000_000_010_000_000_000, 100_000_001);
      assetManager.withdraw(branchChainId2, address(hub), address(1), 1_000_000_010_000_000_000);

      vm.expectEmit();
      emit IAssetManager.Withdrawn(branchChainId2, address(hub), address(1), 1_000_000_000_000_000_000, 100_000_000);
      assetManager.withdraw(branchChainId2, address(hub), address(1), 1_000_000_001_000_000_000);

      vm.stopPrank();
    }

    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vlfVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(hub));
    vlfVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(10_000_000_000 ether));
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.maxDepositFromChainId, (address(1), branchChainId1)),
      false,
      abi.encode(type(uint256).max)
    );
    vlfVault.setRet(
      abi.encodeCall(IVLFVault.maxDepositFromChainId, (address(1), branchChainId2)),
      false,
      abi.encode(type(uint256).max)
    );

    vm.startPrank(owner);
    vm.expectEmit();
    emit IAssetManager.VLFInitialized(address(hub), branchChainId1, address(vlfVault), branchAsset1);
    assetManager.initializeVLF(branchChainId1, address(vlfVault));
    assetManager.setStrategist(address(vlfVault), address(1));

    assetManager.initializeVLF(branchChainId2, address(vlfVault));

    vm.stopPrank();

    {
      vm.startPrank(address(1));
      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.VLFAllocated(address(1), branchChainId1, address(vlfVault), 1 * 10 ** 18, 1 * 10 ** 18);
      assetManager.allocateVLF(branchChainId1, address(vlfVault), 1 * 10 ** 18);

      vm.expectEmit();
      emit IAssetManager.VLFAllocated(address(1), branchChainId1, address(vlfVault), 1000 * 10 ** 18, 1000 * 10 ** 18);
      assetManager.allocateVLF(branchChainId1, address(vlfVault), 1000 * 10 ** 18);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.VLFAllocated(address(1), branchChainId2, address(vlfVault), 1 * 10 ** 18, 1 * 10 ** 8);
      assetManager.allocateVLF(branchChainId2, address(vlfVault), 1 * 10 ** 18);

      // 1_000_000_000 000 00000 00000 00000
      vm.expectEmit();
      emit IAssetManager.VLFAllocated(
        address(1), branchChainId2, address(vlfVault), 1_000_000_000_000_000_000, 1 * 10 ** 8
      );
      assetManager.allocateVLF(branchChainId2, address(vlfVault), 1_000_000_001_000_000_000);

      vm.expectEmit();
      emit IAssetManager.VLFAllocated(
        address(1), branchChainId2, address(vlfVault), 1_000_000_000 * 10 ** 18, 1_000_000_000 * 10 ** 8
      );
      assetManager.allocateVLF(branchChainId2, address(vlfVault), 1_000_000_000 * 10 ** 18);

      vm.stopPrank();
    }

    vm.startPrank(address(entrypoint));
    {
      uint256 amount;

      amount = 1 * 10 ** 18;
      vlfVault.setRet(
        abi.encodeCall(IVLFVault.depositFromChainId, (amount, address(1), branchChainId1)), false, abi.encode(amount)
      );

      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.DepositedWithSupplyVLF(
        branchChainId1, address(hub), address(1), address(vlfVault), amount, amount
      );
      assetManager.depositWithSupplyVLF(branchChainId1, branchAsset1, address(1), address(vlfVault), amount);

      // Hub: 18, Branch: 8
      amount = 1 * 10 ** 8;
      vlfVault.setRet(
        abi.encodeCall(IVLFVault.depositFromChainId, (1 * 10 ** 18, address(1), branchChainId2)),
        false,
        abi.encode(1 * 10 ** 18)
      );

      vm.expectEmit();
      emit IAssetManager.DepositedWithSupplyVLF(
        branchChainId2, address(hub), address(1), address(vlfVault), 1 * 10 ** 18, 1 * 10 ** 18
      );
      assetManager.depositWithSupplyVLF(branchChainId2, branchAsset1, address(1), address(vlfVault), amount);

      amount = 122_022_001;
      vlfVault.setRet(
        abi.encodeCall(IVLFVault.depositFromChainId, (122_022_001 * 10 ** (18 - 8), address(1), branchChainId2)),
        false,
        abi.encode(122_022_001 * 10 ** (18 - 8))
      );

      vm.expectEmit();
      emit IAssetManager.DepositedWithSupplyVLF(
        branchChainId2,
        address(hub),
        address(1),
        address(vlfVault),
        122_022_001 * 10 ** (18 - 8),
        122_022_001 * 10 ** (18 - 8)
      );
      assetManager.depositWithSupplyVLF(branchChainId2, branchAsset1, address(1), address(vlfVault), amount);

      amount = 11_022_001;
      vlfVault.setRet(
        abi.encodeCall(IVLFVault.depositFromChainId, (11_022_001 * 10 ** (18 - 8), address(1), branchChainId2)),
        false,
        abi.encode(11_022_001 * 10 ** (18 - 8))
      );

      vm.expectEmit();
      emit IAssetManager.DepositedWithSupplyVLF(
        branchChainId2,
        address(hub),
        address(1),
        address(vlfVault),
        11_022_001 * 10 ** (18 - 8),
        11_022_001 * 10 ** (18 - 8)
      );
      assetManager.depositWithSupplyVLF(branchChainId2, branchAsset1, address(1), address(vlfVault), amount);
    }

    {
      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.VLFDeallocated(branchChainId1, address(vlfVault), 1 * 10 ** 18);
      assetManager.deallocateVLF(branchChainId1, address(vlfVault), 1 * 10 ** 18);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.VLFDeallocated(branchChainId2, address(vlfVault), 1 * 10 ** 18);
      assetManager.deallocateVLF(branchChainId2, address(vlfVault), 1 * 10 ** 8);

      vm.expectEmit();
      emit IAssetManager.VLFDeallocated(branchChainId2, address(vlfVault), (101_010_101 * 10 ** 8) * 10 ** (18 - 8));
      assetManager.deallocateVLF(branchChainId2, address(vlfVault), 101_010_101 * 10 ** 8);

      vm.expectEmit();
      emit IAssetManager.VLFDeallocated(branchChainId2, address(vlfVault), 112233445123 * 10 ** (18 - 8));
      assetManager.deallocateVLF(branchChainId2, address(vlfVault), 112233445123);
    }

    {
      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.VLFRewardSettled(branchChainId1, address(vlfVault), address(hub), 100);
      assetManager.settleVLFYield(branchChainId1, address(vlfVault), 100);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.VLFRewardSettled(branchChainId2, address(vlfVault), address(hub), 100 * 10 ** (18 - 8));
      assetManager.settleVLFYield(branchChainId2, address(vlfVault), 100);

      vm.expectEmit();
      emit IAssetManager.VLFRewardSettled(
        branchChainId2, address(vlfVault), address(hub), 112233445123 * 10 ** (18 - 8)
      );
      assetManager.settleVLFYield(branchChainId2, address(vlfVault), 112233445123);
    }

    {
      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.VLFLossSettled(branchChainId1, address(vlfVault), address(hub), 100);
      assetManager.settleVLFLoss(branchChainId1, address(vlfVault), 100);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.VLFLossSettled(branchChainId2, address(vlfVault), address(hub), 100 * 10 ** (18 - 8));
      assetManager.settleVLFLoss(branchChainId2, address(vlfVault), 100);

      vm.expectEmit();
      emit IAssetManager.VLFLossSettled(branchChainId2, address(vlfVault), address(hub), 112233445123 * 10 ** (18 - 8));
      assetManager.settleVLFLoss(branchChainId2, address(vlfVault), 112233445123);
    }

    {
      // Hub: 18, Branch: 18
      vm.expectEmit();
      emit IAssetManager.VLFRewardSettled(branchChainId1, address(vlfVault), address(hub), 100);
      assetManager.settleVLFExtraRewards(branchChainId1, address(vlfVault), address(branchAsset1), 100);

      // Hub: 18, Branch: 8
      vm.expectEmit();
      emit IAssetManager.VLFRewardSettled(branchChainId2, address(vlfVault), address(hub), 100 * 10 ** (18 - 8));
      assetManager.settleVLFExtraRewards(branchChainId2, address(vlfVault), address(branchAsset1), 100);

      vm.expectEmit();
      emit IAssetManager.VLFRewardSettled(
        branchChainId2, address(vlfVault), address(hub), 112233445123 * 10 ** (18 - 8)
      );
      assetManager.settleVLFExtraRewards(branchChainId2, address(vlfVault), address(branchAsset1), 112233445123);
    }
    vm.stopPrank();

    // Hub.decimals < Branch.decimals
    vm.prank(owner);
    vm.expectRevert(_errInvalidParameter('branchAssetDecimals'));
    assetManager.setAssetPair(address(hub), branchChainId1, branchAsset2, 24);
  }

  function test_isLiquidityManager() public {
    bytes32 liquidityManagerRole = assetManager.LIQUIDITY_MANAGER_ROLE();

    // Initially user1 should not be a liquidity manager
    assertFalse(assetManager.isLiquidityManager(user1));

    vm.prank(owner);
    assetManager.grantRole(liquidityManagerRole, user1);
    assertTrue(assetManager.isLiquidityManager(user1));

    vm.prank(owner);
    assetManager.revokeRole(liquidityManagerRole, user1);
    assertFalse(assetManager.isLiquidityManager(user1));
  }

  function test_setBranchLiquidityThreshold() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setAssetPair(address(hubAsset), branchChainId2, branchAsset2, 18);

    vm.startPrank(liquidityManager);

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 100 ether);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 100 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 100 ether);

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 30 ether);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 30 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 30 ether);

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 0);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 0);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 0);

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId2, 50 ether);
    assetManager.setBranchLiquidityThreshold(branchChainId2, address(hubAsset), 50 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId2), 50 ether);

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 80 ether);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 80 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 80 ether);

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 0);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 0);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 0);

    vm.stopPrank();
  }

  function test_setBranchLiquidityThreshold_Unauthorized() public {
    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.LIQUIDITY_MANAGER_ROLE()));
    vm.prank(user1);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 100 ether);
  }

  function test_setBranchLiquidityThreshold_HubAssetPairNotExist() public {
    vm.startPrank(liquidityManager);
    vm.expectRevert(_errHubAssetPairNotExist(address(hubAsset)));
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 100 ether);
  }

  function test_setBranchLiquidityThreshold_batch() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setAssetPair(address(hubAsset), branchChainId2, branchAsset2, 18);

    vm.startPrank(liquidityManager);

    uint256[] memory chainIds = new uint256[](2);
    address[] memory hubAssets = new address[](2);
    uint256[] memory thresholds = new uint256[](2);

    chainIds[0] = branchChainId1;
    hubAssets[0] = address(hubAsset);
    thresholds[0] = 50 ether;
    chainIds[1] = branchChainId2;
    hubAssets[1] = address(hubAsset);
    thresholds[1] = 100 ether;

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 50 ether);
    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId2, 100 ether);
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);

    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 50 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId2), 100 ether);

    chainIds[0] = branchChainId1;
    hubAssets[0] = address(hubAsset);
    thresholds[0] = 70 ether;
    chainIds[1] = branchChainId2;
    hubAssets[1] = address(hubAsset);
    thresholds[1] = 120 ether;

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 70 ether);
    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId2, 120 ether);
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);

    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 70 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId2), 120 ether);

    chainIds[0] = branchChainId1;
    hubAssets[0] = address(hubAsset);
    thresholds[0] = 20 ether;
    chainIds[1] = branchChainId2;
    hubAssets[1] = address(hubAsset);
    thresholds[1] = 5 ether;

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 20 ether);
    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId2, 5 ether);
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);

    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 20 ether);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId2), 5 ether);

    chainIds[0] = branchChainId1;
    hubAssets[0] = address(hubAsset);
    thresholds[0] = 0;
    chainIds[1] = branchChainId2;
    hubAssets[1] = address(hubAsset);
    thresholds[1] = 0;

    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId1, 0);
    vm.expectEmit();
    emit IAssetManagerStorageV1.BranchLiquidityThresholdSet(address(hubAsset), branchChainId2, 0);
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);

    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId1), 0);
    assertEq(assetManager.branchLiquidityThreshold(address(hubAsset), branchChainId2), 0);

    vm.stopPrank();
  }

  function test_setBranchLiquidityThreshold_batch_Unauthorized() public {
    uint256[] memory chainIds = new uint256[](2);
    address[] memory hubAssets = new address[](2);
    uint256[] memory thresholds = new uint256[](2);

    chainIds[0] = branchChainId1;
    hubAssets[0] = address(hubAsset);
    thresholds[0] = 50 ether;
    chainIds[1] = branchChainId2;
    hubAssets[1] = address(hubAsset);
    thresholds[1] = 100 ether;

    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.LIQUIDITY_MANAGER_ROLE()));
    vm.prank(user1);
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);
  }

  function test_setBranchLiquidityThreshold_batch_HubAssetPairNotExist() public {
    uint256[] memory chainIds = new uint256[](2);
    address[] memory hubAssets = new address[](2);
    uint256[] memory thresholds = new uint256[](2);

    chainIds[0] = branchChainId1;
    hubAssets[0] = address(hubAsset);
    thresholds[0] = 50 ether;
    chainIds[1] = branchChainId2;
    hubAssets[1] = address(hubAsset);
    thresholds[1] = 100 ether;

    vm.prank(liquidityManager);
    vm.expectRevert(_errHubAssetPairNotExist(address(hubAsset)));
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);
  }

  function test_initializeVLF() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), true);

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManager.VLFInitialized(address(hubAsset), branchChainId1, address(vlfVault), branchAsset1);
    assetManager.initializeVLF(branchChainId1, address(vlfVault));

    assertTrue(assetManager.vlfInitialized(branchChainId1, address(vlfVault)));
  }

  function test_initializeVLF_Unauthorized() public {
    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.DEFAULT_ADMIN_ROLE()));
    vm.prank(user1);
    assetManager.initializeVLF(branchChainId1, address(vlfVault));
  }

  function test_initializeVLF_VLFVaultFactoryNotSet() public {
    vm.prank(owner);
    vm.expectRevert(_errVLFVaultFactoryNotSet());
    assetManager.initializeVLF(branchChainId1, address(vlfVault));
  }

  function test_initializeVLF_InvalidVLFVault() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), false);

    vm.prank(owner);
    vm.expectRevert(_errInvalidVLFVault(address(vlfVault)));
    assetManager.initializeVLF(branchChainId1, address(vlfVault));
  }

  function test_initializeVLF_BranchAssetPairNotExist() public {
    _setVLFVaultInstance(address(vlfVault), true);

    vm.prank(owner);
    assetManager.setVLFVaultFactory(address(vlfFactory));

    vm.prank(owner);
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, address(0)));
    assetManager.initializeVLF(branchChainId1, address(vlfVault));
  }

  function test_initializeVLF_VLFAlreadyInitialized() public {
    test_initializeVLF();
    assertTrue(assetManager.vlfInitialized(branchChainId1, address(vlfVault)));

    vm.prank(owner);
    vm.expectRevert(_errVLFAlreadyInitialized(branchChainId1, address(vlfVault)));
    assetManager.initializeVLF(branchChainId1, address(vlfVault));
  }

  function test_setAssetPair() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);

    assertEq(assetManager.branchAsset(address(hubAsset), branchChainId1), branchAsset1);
  }

  function test_setAssetPair_Unauthorized() public {
    vm.expectRevert(_errAccessControlUnauthorized(address(this), assetManager.DEFAULT_ADMIN_ROLE()));
    assetManager.setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
  }

  function test_setAssetPair_InvalidParameter() public {
    _setHubAssetFactory();
    _setHubAssetInstance(address(0), false);
    _setHubAssetInstance(user1, false);
    _setHubAssetInstance(address(hubAsset), true);

    vm.startPrank(owner);

    vm.expectRevert(_errInvalidHubAsset(address(0)));
    assetManager.setAssetPair(address(0), branchChainId1, branchAsset1, 18);

    vm.expectRevert(_errInvalidHubAsset(user1));
    assetManager.setAssetPair(user1, branchChainId1, branchAsset1, 18);

    vm.stopPrank();
  }

  function test_setEntrypoint() public {
    assertEq(assetManager.entrypoint(), address(entrypoint));

    MockContract newEntrypoint = new MockContract();

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.EntrypointSet(address(newEntrypoint));
    assetManager.setEntrypoint(address(newEntrypoint));

    assertEq(assetManager.entrypoint(), address(newEntrypoint));
  }

  function test_setEntrypoint_Unauthorized() public {
    address newEntrypoint = address(new MockContract());

    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.DEFAULT_ADMIN_ROLE()));
    vm.prank(user1);
    assetManager.setEntrypoint(newEntrypoint);
  }

  function test_setEntrypoint_InvalidParameter() public {
    vm.startPrank(owner);

    vm.expectRevert(_errInvalidParameter('Entrypoint'));
    assetManager.setEntrypoint(address(0));

    vm.expectRevert(_errInvalidParameter('Entrypoint'));
    assetManager.setEntrypoint(user1);

    vm.stopPrank();
  }

  function test_setReclaimQueue() public {
    assertEq(assetManager.reclaimQueue(), address(reclaimQueue));

    MockContract newReclaimQueue = new MockContract();

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.ReclaimQueueSet(address(newReclaimQueue));
    assetManager.setReclaimQueue(address(newReclaimQueue));

    assertEq(assetManager.reclaimQueue(), address(newReclaimQueue));
  }

  function test_setReclaimQueue_Unauthorized() public {
    address newReclaimQueue = address(new MockContract());

    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.DEFAULT_ADMIN_ROLE()));
    vm.prank(user1);
    assetManager.setReclaimQueue(newReclaimQueue);
  }

  function test_setReclaimQueue_InvalidParameter() public {
    vm.startPrank(owner);

    vm.expectRevert(_errInvalidParameter('ReclaimQueue'));
    assetManager.setReclaimQueue(address(0));

    vm.expectRevert(_errInvalidParameter('ReclaimQueue'));
    assetManager.setReclaimQueue(user1);

    vm.stopPrank();
  }

  function test_setTreasury() public {
    assertEq(assetManager.treasury(), address(treasury));

    MockContract newTreasury = new MockContract();

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.TreasurySet(address(newTreasury));
    assetManager.setTreasury(address(newTreasury));

    assertEq(assetManager.treasury(), address(newTreasury));
  }

  function test_setTreasury_Unauthorized() public {
    address newTreasury = address(new MockContract());

    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.DEFAULT_ADMIN_ROLE()));
    vm.prank(user1);
    assetManager.setTreasury(newTreasury);
  }

  function test_setTreasury_InvalidParameter() public {
    vm.startPrank(owner);

    vm.expectRevert(_errInvalidParameter('Treasury'));
    assetManager.setTreasury(address(0));

    vm.expectRevert(_errInvalidParameter('Treasury'));
    assetManager.setTreasury(user1);

    vm.stopPrank();
  }

  function test_setStrategist() public {
    assertEq(assetManager.strategist(address(vlfVault)), address(0));

    vm.prank(owner);
    assetManager.setVLFVaultFactory(address(vlfFactory));

    _setVLFVaultInstance(address(vlfVault), true);

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.StrategistSet(address(vlfVault), strategist);
    assetManager.setStrategist(address(vlfVault), strategist);

    assertEq(assetManager.strategist(address(vlfVault)), strategist);

    address newStrategist = makeAddr('newStrategist');

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.StrategistSet(address(vlfVault), newStrategist);
    assetManager.setStrategist(address(vlfVault), newStrategist);

    assertEq(assetManager.strategist(address(vlfVault)), newStrategist);
  }

  function test_setStrategist_Unauthorized() public {
    vm.expectRevert(_errAccessControlUnauthorized(user1, assetManager.DEFAULT_ADMIN_ROLE()));
    vm.prank(user1);
    assetManager.setStrategist(address(vlfVault), strategist);
  }

  function test_setStrategist_VLFVaultFactoryNotSet() public {
    vm.prank(owner);
    vm.expectRevert(_errVLFVaultFactoryNotSet());
    assetManager.setStrategist(address(vlfVault), strategist);
  }

  function test_setStrategist_InvalidVLF() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1, 18);
    _setVLFVaultFactory();
    _setVLFVaultInstance(address(vlfVault), false);

    vm.prank(owner);
    vm.expectRevert(_errInvalidVLFVault(address(vlfVault)));
    assetManager.setStrategist(address(vlfVault), strategist);
  }

  function _setAssetPair(address hubAsset_, uint256 chainId_, address branchAsset_, uint8 branchAssetDecimals_)
    internal
  {
    _setHubAssetFactory();
    _setHubAssetInstance(address(hubAsset_), true);

    vm.prank(owner);
    assetManager.setAssetPair(hubAsset_, chainId_, branchAsset_, branchAssetDecimals_);

    require(assetManager.branchAssetDecimals(hubAsset_, chainId_) == branchAssetDecimals_, 'branchAssetDecimals');
  }

  function _setHubAssetFactory() internal {
    vm.prank(owner);
    assetManager.setHubAssetFactory(address(hubAssetFactory));
  }

  function _setHubAssetInstance(address hubAsset_, bool isInstance) internal {
    hubAssetFactory.setRet(abi.encodeCall(IBeaconBase.isInstance, (hubAsset_)), false, abi.encode(isInstance));
  }

  function _setVLFVaultFactory() internal {
    vm.prank(owner);
    assetManager.setVLFVaultFactory(address(vlfFactory));
  }

  function _setVLFVaultInstance(address vlf_, bool isInstance) internal {
    vlfFactory.setRet(abi.encodeCall(IBeaconBase.isInstance, (vlf_)), false, abi.encode(isInstance));
  }
}
