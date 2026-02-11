// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';
import { Vm } from '@std/Vm.sol';

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { IERC4626 } from '@oz/interfaces/IERC4626.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ERC20 } from '@oz/token/ERC20/ERC20.sol';

import { AssetManager } from '../../../src/hub/core/AssetManager.sol';
import { AssetManagerStorageV1 } from '../../../src/hub/core/AssetManagerStorageV1.sol';
import { HubAsset } from '../../../src/hub/core/HubAsset.sol';
import { MatrixVaultBasic } from '../../../src/hub/matrix/MatrixVaultBasic.sol';
import { ReclaimQueue } from '../../../src/hub/ReclaimQueue.sol';
import { Treasury } from '../../../src/hub/reward/Treasury.sol';
import { IAssetManager, IAssetManagerStorageV1 } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { IAssetManagerEntrypoint } from '../../../src/interfaces/hub/core/IAssetManagerEntrypoint.sol';
import { IHubAsset } from '../../../src/interfaces/hub/core/IHubAsset.sol';
import { IEOLVault } from '../../../src/interfaces/hub/eol/IEOLVault.sol';
import { IEOLVaultFactory } from '../../../src/interfaces/hub/eol/IEOLVaultFactory.sol';
import { IMatrixVault } from '../../../src/interfaces/hub/matrix/IMatrixVault.sol';
import { IMatrixVaultFactory } from '../../../src/interfaces/hub/matrix/IMatrixVaultFactory.sol';
import { IReclaimQueue } from '../../../src/interfaces/hub/matrix/IReclaimQueue.sol';
import { ITreasury } from '../../../src/interfaces/hub/reward/ITreasury.sol';
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

  function _errMatrixVaultFactoryNotSet() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__MatrixVaultFactoryNotSet.selector);
  }

  function _errMatrixNotInitialized(uint256 chainId, address matrixVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__MatrixNotInitialized.selector, chainId, matrixVault
    );
  }

  function _errMatrixAlreadyInitialized(uint256 chainId, address matrixVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__MatrixAlreadyInitialized.selector, chainId, matrixVault
    );
  }

  function _errEOLVaultFactoryNotSet() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__EOLVaultFactoryNotSet.selector);
  }

  function _errEOLNotInitialized(uint256 chainId, address eolVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__EOLNotInitialized.selector, chainId, eolVault
    );
  }

  function _errEOLAlreadyInitialized(uint256 chainId, address eolVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IAssetManagerStorageV1.IAssetManagerStorageV1__EOLAlreadyInitialized.selector, chainId, eolVault
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

  function _errInvalidEOLVault(address eolVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__InvalidEOLVault.selector, eolVault);
  }

  function _errInvalidMatrixVault(address matrixVault) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(IAssetManagerStorageV1.IAssetManagerStorageV1__InvalidMatrixVault.selector, matrixVault);
  }

  function _errMatrixNothingToReserve(address matrixVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManager.IAssetManager__NothingToReserve.selector, matrixVault);
  }

  function _errMatrixInsufficient(address matrixVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IAssetManager.IAssetManager__MatrixInsufficient.selector, matrixVault);
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
  MockContract matrixVault;
  MockContract matrixVaultFactory;
  MockContract eolVault;
  MockContract eolVaultFactory;
  MockContract hubAsset;
  MockContract hubAssetFactory;

  AssetManager assetManager;

  address owner = makeAddr('owner');
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
    entrypoint.setCall(IAssetManagerEntrypoint.allocateMatrix.selector);
    entrypoint.setCall(IAssetManagerEntrypoint.initializeAsset.selector);
    entrypoint.setCall(IAssetManagerEntrypoint.initializeMatrix.selector);
    entrypoint.setCall(IAssetManagerEntrypoint.initializeEOL.selector);

    treasury = new MockContract();
    treasury.setCall(ITreasury.storeRewards.selector);

    matrixVault = new MockContract();
    matrixVault.setCall(IERC4626.deposit.selector);
    matrixVaultFactory = new MockContract();

    eolVault = new MockContract();
    eolVault.setCall(IERC4626.deposit.selector);
    eolVaultFactory = new MockContract();

    hubAsset = new MockContract();
    hubAsset.setCall(IHubAsset.mint.selector);
    hubAsset.setCall(IHubAsset.burn.selector);
    hubAsset.setCall(IERC20.approve.selector);
    hubAsset.setCall(IERC20.transfer.selector);
    hubAsset.setCall(IERC20.transferFrom.selector);

    hubAssetFactory = new MockContract();

    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    eolVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));

    assetManager = AssetManager(
      payable(
        new ERC1967Proxy(
          address(new AssetManager()), abi.encodeCall(AssetManager.initialize, (owner, address(treasury)))
        )
      )
    );

    vm.startPrank(owner);
    assetManager.setReclaimQueue(address(reclaimQueue));
    assetManager.setEntrypoint(address(entrypoint));
    vm.stopPrank();
  }

  function test_deposit() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.Deposited(branchChainId1, address(hubAsset), user1, 100 ether);
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (user1, 100 ether)));
  }

  function test_deposit_Unauthorized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);
  }

  function test_deposit_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchAsset1));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);
  }

  function test_depositWithSupplyMatrix() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), true);

    vm.prank(owner);
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));

    // vault.asset != hubAsset

    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(branchAsset1)));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyMatrix(
      branchChainId1, address(hubAsset), user1, address(matrixVault), 100 ether, 0
    );
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (user1, 100 ether)));

    // maxDeposit > amount

    hubAsset.setRet(abi.encodeCall(IERC20.approve, (address(matrixVault), 100 ether)), false, abi.encode(true));
    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    matrixVault.setRet(abi.encodeCall(IERC4626.maxDeposit, (user1)), false, abi.encode(101 ether));
    matrixVault.setRet(abi.encodeCall(IERC4626.deposit, (100 ether, user1)), false, abi.encode(100 ether));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyMatrix(
      branchChainId1, address(hubAsset), user1, address(matrixVault), 100 ether, 100 ether
    );
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.approve, (address(matrixVault), 100 ether)));
    matrixVault.assertLastCall(abi.encodeCall(IERC4626.deposit, (100 ether, user1)));

    // maxDeposit < amount

    hubAsset.setRet(abi.encodeCall(IERC20.approve, (address(matrixVault), 99 ether)), false, abi.encode(true));
    hubAsset.setRet(abi.encodeCall(IERC20.transfer, (user1, 1 ether)), false, abi.encode(true));
    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    matrixVault.setRet(abi.encodeCall(IERC4626.maxDeposit, (user1)), false, abi.encode(99 ether));
    matrixVault.setRet(abi.encodeCall(IERC4626.deposit, (99 ether, user1)), false, abi.encode(99 ether));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyMatrix(
      branchChainId1, address(hubAsset), user1, address(matrixVault), 100 ether, 99 ether
    );
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.approve, (address(matrixVault), 99 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.transfer, (address(user1), 1 ether)));
    matrixVault.assertLastCall(abi.encodeCall(IERC4626.deposit, (99 ether, user1)));
  }

  function test_depositWithSupplyMatrix_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);
  }

  /// @dev No occurrence case until methods like unsetAssetPair are added.
  function test_depositWithSupplyMatrix_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchAsset1));
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);
  }

  function test_depositWithSupplyMatrix_MatrixNotInitialized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), true);

    vm.prank(address(entrypoint));
    vm.expectRevert(_errMatrixNotInitialized(branchChainId1, address(matrixVault)));
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);
  }

  function test_depositWithSupplyEOL() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setEOLVaultFactory();
    _setEOLVaultInstance(address(eolVault), true);

    vm.prank(owner);
    assetManager.initializeEOL(branchChainId1, address(eolVault));

    // vault.asset != hubAsset
    eolVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(branchAsset1)));

    vm.prank(address(entrypoint));
    emit IAssetManager.DepositedWithSupplyEOL(branchChainId1, address(hubAsset), user1, address(eolVault), 100 ether, 0);
    assetManager.depositWithSupplyEOL(branchChainId1, branchAsset1, user1, address(eolVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (user1, 100 ether)));

    // vault.asset == hubAsset
    hubAsset.setRet(abi.encodeCall(IERC20.approve, (address(eolVault), 100 ether)), false, abi.encode(true));
    eolVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    eolVault.setRet(abi.encodeCall(IERC4626.deposit, (100 ether, user1)), false, abi.encode(100 ether));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.DepositedWithSupplyEOL(
      branchChainId1, address(hubAsset), user1, address(eolVault), 100 ether, 100 ether
    );
    assetManager.depositWithSupplyEOL(branchChainId1, branchAsset1, user1, address(eolVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    hubAsset.assertLastCall(abi.encodeCall(IERC20.approve, (address(eolVault), 100 ether)));
    eolVault.assertLastCall(abi.encodeCall(IERC4626.deposit, (100 ether, user1)));
  }

  function test_depositWithSupplyEOL_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.depositWithSupplyEOL(branchChainId1, branchAsset1, user1, address(eolVault), 100 ether);
  }

  /// @dev No occurrence case until methods like unsetAssetPair are added.
  function test_depositWithSupplyEOL_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchAsset1));
    assetManager.depositWithSupplyEOL(branchChainId1, branchAsset1, user1, address(eolVault), 100 ether);
  }

  function test_depositWithSupplyEOL_EOLNotInitialized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(address(entrypoint));
    vm.expectRevert(_errEOLNotInitialized(branchChainId1, address(eolVault)));
    assetManager.depositWithSupplyEOL(branchChainId1, branchAsset1, user1, address(eolVault), 100 ether);
  }

  function test_withdraw() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(user1);
    vm.expectEmit();
    emit IAssetManager.Withdrawn(branchChainId1, address(hubAsset), user1, 100 ether);
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
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(user1);
    vm.expectRevert(_errZeroToAddress());
    assetManager.withdraw(branchChainId1, address(hubAsset), address(0), 100 ether);
  }

  function test_withdraw_ZeroAmount() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(user1);
    vm.expectRevert(_errZeroAmount());
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 0);
  }

  function test_withdraw_BranchAvailableLiquidityInsufficient() public {
    test_allocateMatrix();

    vm.prank(user1);
    vm.expectRevert(_errBranchAvailableLiquidityInsufficient(branchChainId1, address(hubAsset), 200 ether, 201 ether));
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 201 ether);
  }

  function test_withdraw_BranchLiquidityThresholdNotSatisfied() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(address(entrypoint));
    assetManager.deposit(branchChainId1, branchAsset1, user1, 100 ether);

    vm.prank(owner);
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 80 ether);

    vm.prank(user1);
    vm.expectRevert(_errBranchLiquidityThresholdNotSatisfied(branchChainId1, address(hubAsset), 80 ether, 21 ether));
    assetManager.withdraw(branchChainId1, address(hubAsset), user1, 21 ether);
  }

  function test_allocateMatrix() public {
    test_depositWithSupplyMatrix();

    vm.prank(owner);
    assetManager.setStrategist(address(matrixVault), strategist);

    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(200 ether));

    vm.prank(strategist);
    vm.expectEmit();
    emit IAssetManager.MatrixAllocated(strategist, branchChainId1, address(matrixVault), 100 ether);
    assetManager.allocateMatrix(branchChainId1, address(matrixVault), 100 ether);
  }

  function test_allocateMatrix_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.allocateMatrix(branchChainId1, address(matrixVault), 100 ether);
  }

  function test_allocateMatrix_MatrixNotInitialized() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), true);

    vm.prank(owner);
    assetManager.setStrategist(address(matrixVault), strategist);

    vm.prank(strategist);
    vm.expectRevert(_errMatrixNotInitialized(branchChainId1, address(matrixVault)));
    assetManager.allocateMatrix(branchChainId1, address(matrixVault), 100 ether);
  }

  function test_allocateMatrix_MatrixInsufficient() public {
    test_depositWithSupplyMatrix();

    vm.prank(owner);
    assetManager.setStrategist(address(matrixVault), strategist);

    // mint 100 of hubAsset to user1
    matrixVault.setRet(abi.encodeCall(IERC4626.maxDeposit, (user1)), false, abi.encode(100 ether));
    vm.prank(address(entrypoint));
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);

    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(100 ether));

    vm.prank(strategist);
    vm.expectRevert(_errMatrixInsufficient(address(matrixVault)));
    assetManager.allocateMatrix(branchChainId1, address(matrixVault), 101 ether);
  }

  function test_allocateMatrix_BranchAvailableLiquidityInsufficient() public {
    test_depositWithSupplyMatrix();

    vm.startPrank(owner);
    assetManager.setAssetPair(address(hubAsset), branchChainId2, branchAsset2);
    assetManager.initializeMatrix(branchChainId2, address(matrixVault));
    assetManager.setStrategist(address(matrixVault), strategist);
    vm.stopPrank();

    // mint 100 of hubAsset to user1 for each branch chains
    matrixVault.setRet(abi.encodeCall(IERC4626.maxDeposit, (user1)), false, abi.encode(100 ether));
    vm.startPrank(address(entrypoint));
    assetManager.depositWithSupplyMatrix(branchChainId1, branchAsset1, user1, address(matrixVault), 100 ether);
    assetManager.depositWithSupplyMatrix(branchChainId2, branchAsset2, user1, address(matrixVault), 100 ether);
    vm.stopPrank();

    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(500 ether));

    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId1), 400 ether);
    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId2), 100 ether);
    assertEq(assetManager.matrixIdle(address(matrixVault)), 500 ether);
    assertEq(assetManager.matrixAlloc(address(matrixVault)), 0 ether);

    vm.startPrank(strategist);
    assetManager.allocateMatrix(branchChainId1, address(matrixVault), 30 ether);
    assetManager.allocateMatrix(branchChainId2, address(matrixVault), 50 ether);
    vm.stopPrank();

    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId1), 370 ether);
    assertEq(assetManager.branchAvailableLiquidity(address(hubAsset), branchChainId2), 50 ether);
    assertEq(assetManager.matrixIdle(address(matrixVault)), 420 ether);
    assertEq(assetManager.matrixAlloc(address(matrixVault)), 80 ether);

    vm.prank(strategist);
    vm.expectRevert(_errBranchAvailableLiquidityInsufficient(branchChainId1, address(hubAsset), 370 ether, 371 ether));
    assetManager.allocateMatrix(branchChainId1, address(matrixVault), 371 ether);

    vm.prank(strategist);
    vm.expectRevert(_errBranchAvailableLiquidityInsufficient(branchChainId2, address(hubAsset), 50 ether, 51 ether));
    assetManager.allocateMatrix(branchChainId2, address(matrixVault), 51 ether);
  }

  function test_deallocateMatrix() public {
    test_allocateMatrix(); // load 200 hubAssets
    assertEq(assetManager.matrixIdle(address(matrixVault)), 100 ether);
    assertEq(assetManager.matrixAlloc(address(matrixVault)), 100 ether);

    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));
    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(100 ether));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.MatrixDeallocated(branchChainId1, address(matrixVault), 100 ether);
    assetManager.deallocateMatrix(branchChainId1, address(matrixVault), 100 ether);

    assertEq(assetManager.matrixIdle(address(matrixVault)), 100 ether);
    assertEq(assetManager.matrixAlloc(address(matrixVault)), 0);
  }

  function test_deallocateMatrix_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.deallocateMatrix(branchChainId1, address(matrixVault), 100 ether);
  }

  function test_reserveMatrix() public {
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), true);

    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(200 ether));
    reclaimQueue.setRet(
      abi.encodeCall(IReclaimQueue.previewSync, (address(matrixVault), 100)), false, abi.encode(0, 100 ether)
    );
    reclaimQueue.setRet(
      abi.encodeCall(IReclaimQueue.sync, (strategist, address(matrixVault), 100)), false, abi.encode(100, 100 ether)
    );

    vm.prank(owner);
    assetManager.setStrategist(address(matrixVault), strategist);

    vm.prank(strategist);
    vm.expectEmit();
    emit IAssetManager.MatrixReserved(strategist, address(matrixVault), 100, 100, 100 ether);
    assetManager.reserveMatrix(address(matrixVault), 100);

    reclaimQueue.assertLastCall(abi.encodeCall(IReclaimQueue.sync, (strategist, address(matrixVault), 100)));
  }

  function test_reserveMatrix_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.reserveMatrix(address(matrixVault), 10);
  }

  function test_reserveMatrix_MatrixNothingToReserve() public {
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), true);

    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(200 ether));
    reclaimQueue.setRet(abi.encodeCall(IReclaimQueue.previewSync, (address(matrixVault), 100)), false, abi.encode(0, 0));

    vm.prank(owner);
    assetManager.setStrategist(address(matrixVault), strategist);

    vm.prank(strategist);
    vm.expectRevert(_errMatrixNothingToReserve(address(matrixVault)));
    assetManager.reserveMatrix(address(matrixVault), 100);
  }

  function test_reserveMatrix_MatrixInsufficient() public {
    test_initializeMatrix();

    vm.prank(owner);
    assetManager.setStrategist(address(matrixVault), strategist);

    matrixVault.setRet(abi.encodeCall(IERC4626.totalAssets, ()), false, abi.encode(100 ether));
    reclaimQueue.setRet(
      abi.encodeCall(IReclaimQueue.previewSync, (address(matrixVault), 100)), false, abi.encode(0, 200 ether)
    );

    vm.prank(strategist);
    vm.expectRevert(_errMatrixInsufficient(address(matrixVault)));
    assetManager.reserveMatrix(address(matrixVault), 100);
  }

  function test_settleMatrixYield() public {
    test_allocateMatrix();

    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.MatrixRewardSettled(branchChainId1, address(matrixVault), address(hubAsset), 100 ether);
    assetManager.settleMatrixYield(branchChainId1, address(matrixVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(matrixVault), 100 ether)));
  }

  function test_settleMatrixYield_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.settleMatrixYield(branchChainId1, address(matrixVault), 100 ether);
  }

  function test_settleMatrixLoss() public {
    test_allocateMatrix();

    matrixVault.setRet(abi.encodeCall(IERC4626.asset, ()), false, abi.encode(address(hubAsset)));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.MatrixLossSettled(branchChainId1, address(matrixVault), address(hubAsset), 100 ether);
    assetManager.settleMatrixLoss(branchChainId1, address(matrixVault), 100 ether);

    hubAsset.assertLastCall(abi.encodeCall(IHubAsset.burn, (address(matrixVault), 100 ether)));
  }

  function test_settleMatrixLoss_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.settleMatrixLoss(branchChainId1, address(matrixVault), 10 ether);
  }

  function test_settleMatrixExtraRewards() public {
    MockContract rewardToken = new MockContract();
    rewardToken.setCall(IERC20.approve.selector);
    rewardToken.setCall(IHubAsset.mint.selector);
    rewardToken.setRet(abi.encodeCall(IERC20.approve, (address(treasury), 100 ether)), false, abi.encode(true));

    _setAssetPair(address(rewardToken), branchChainId1, branchRewardTokenAddress);

    vm.prank(owner);
    assetManager.setTreasury(address(treasury));

    vm.prank(address(entrypoint));
    vm.expectEmit();
    emit IAssetManager.MatrixRewardSettled(branchChainId1, address(matrixVault), address(rewardToken), 100 ether);
    assetManager.settleMatrixExtraRewards(branchChainId1, address(matrixVault), branchRewardTokenAddress, 100 ether);

    rewardToken.assertLastCall(abi.encodeCall(IHubAsset.mint, (address(assetManager), 100 ether)));
    rewardToken.assertLastCall(abi.encodeCall(IERC20.approve, (address(treasury), 100 ether)));

    treasury.assertLastCall(
      abi.encodeCall(ITreasury.storeRewards, (address(matrixVault), address(rewardToken), 100 ether))
    );
  }

  function test_settleMatrixExtraRewards_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    assetManager.settleMatrixExtraRewards(branchChainId1, address(matrixVault), branchRewardTokenAddress, 100 ether);
  }

  function test_settleMatrixExtraRewards_BranchAssetPairNotExist() public {
    vm.prank(address(entrypoint));
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, branchRewardTokenAddress));
    assetManager.settleMatrixExtraRewards(branchChainId1, address(matrixVault), branchRewardTokenAddress, 100 ether);
  }

  function test_initializeAsset() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManager.AssetInitialized(address(hubAsset), branchChainId1, branchAsset1);
    assetManager.initializeAsset(branchChainId1, address(hubAsset));

    entrypoint.assertLastCall(abi.encodeCall(IAssetManagerEntrypoint.initializeAsset, (branchChainId1, branchAsset1)));

    assertEq(assetManager.branchAsset(address(hubAsset), branchChainId1), branchAsset1);
  }

  function test_initializeAsset_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
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

  function test_setBranchLiquidityThreshold() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setAssetPair(address(hubAsset), branchChainId2, branchAsset2);

    vm.startPrank(owner);

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
    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 100 ether);
  }

  function test_setBranchLiquidityThreshold_HubAssetPairNotExist() public {
    vm.startPrank(owner);
    vm.expectRevert(_errHubAssetPairNotExist(address(hubAsset)));
    assetManager.setBranchLiquidityThreshold(branchChainId1, address(hubAsset), 100 ether);
  }

  function test_setBranchLiquidityThreshold_batch() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setAssetPair(address(hubAsset), branchChainId2, branchAsset2);

    vm.startPrank(owner);

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

    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
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

    vm.prank(owner);
    vm.expectRevert(_errHubAssetPairNotExist(address(hubAsset)));
    assetManager.setBranchLiquidityThreshold(chainIds, hubAssets, thresholds);
  }

  function test_initializeMatrix() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), true);

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManager.MatrixInitialized(address(hubAsset), branchChainId1, address(matrixVault), branchAsset1);
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));

    assertTrue(assetManager.matrixInitialized(branchChainId1, address(matrixVault)));
  }

  function test_initializeMatrix_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));
  }

  function test_initializeMatrix_MatrixVaultFactoryNotSet() public {
    vm.prank(owner);
    vm.expectRevert(_errMatrixVaultFactoryNotSet());
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));
  }

  function test_initializeMatrix_InvalidMatrixVault() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), false);

    vm.prank(owner);
    vm.expectRevert(_errInvalidMatrixVault(address(matrixVault)));
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));
  }

  function test_initializeMatrix_BranchAssetPairNotExist() public {
    _setMatrixVaultInstance(address(matrixVault), true);

    vm.prank(owner);
    assetManager.setMatrixVaultFactory(address(matrixVaultFactory));

    vm.prank(owner);
    vm.expectRevert(_errBranchAssetPairNotExist(branchChainId1, address(0)));
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));
  }

  function test_initializeMatrix_MatrixAlreadyInitialized() public {
    test_initializeMatrix();
    assertTrue(assetManager.matrixInitialized(branchChainId1, address(matrixVault)));

    vm.prank(owner);
    vm.expectRevert(_errMatrixAlreadyInitialized(branchChainId1, address(matrixVault)));
    assetManager.initializeMatrix(branchChainId1, address(matrixVault));
  }

  function test_setAssetPair() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);

    assertEq(assetManager.branchAsset(address(hubAsset), branchChainId1), branchAsset1);
  }

  function test_setAssetPair_Unauthorized() public {
    vm.expectRevert(_errOwnableUnauthorizedAccount(address(this)));
    assetManager.setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
  }

  function test_setAssetPair_InvalidParameter() public {
    _setHubAssetFactory();
    _setHubAssetInstance(address(0), false);
    _setHubAssetInstance(user1, false);
    _setHubAssetInstance(address(hubAsset), true);

    vm.startPrank(owner);

    vm.expectRevert(_errInvalidHubAsset(address(0)));
    assetManager.setAssetPair(address(0), branchChainId1, branchAsset1);

    vm.expectRevert(_errInvalidHubAsset(user1));
    assetManager.setAssetPair(user1, branchChainId1, branchAsset1);

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

    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
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

    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
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

    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
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
    assertEq(assetManager.strategist(address(matrixVault)), address(0));

    vm.prank(owner);
    assetManager.setMatrixVaultFactory(address(matrixVaultFactory));

    _setMatrixVaultInstance(address(matrixVault), true);

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.StrategistSet(address(matrixVault), strategist);
    assetManager.setStrategist(address(matrixVault), strategist);

    assertEq(assetManager.strategist(address(matrixVault)), strategist);

    address newStrategist = makeAddr('newStrategist');

    vm.prank(owner);
    vm.expectEmit();
    emit IAssetManagerStorageV1.StrategistSet(address(matrixVault), newStrategist);
    assetManager.setStrategist(address(matrixVault), newStrategist);

    assertEq(assetManager.strategist(address(matrixVault)), newStrategist);
  }

  function test_setStrategist_Unauthorized() public {
    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
    assetManager.setStrategist(address(matrixVault), strategist);
  }

  function test_setStrategist_MatrixVaultFactoryNotSet() public {
    vm.prank(owner);
    vm.expectRevert(_errMatrixVaultFactoryNotSet());
    assetManager.setStrategist(address(matrixVault), strategist);
  }

  function test_setStrategist_InvalidMatrixVault() public {
    _setAssetPair(address(hubAsset), branchChainId1, branchAsset1);
    _setMatrixVaultFactory();
    _setMatrixVaultInstance(address(matrixVault), false);

    vm.prank(owner);
    vm.expectRevert(_errInvalidMatrixVault(address(matrixVault)));
    assetManager.setStrategist(address(matrixVault), strategist);
  }

  function _setAssetPair(address hubAsset_, uint256 chainId_, address branchAsset_) internal {
    _setHubAssetFactory();
    _setHubAssetInstance(address(hubAsset_), true);

    vm.prank(owner);
    assetManager.setAssetPair(hubAsset_, chainId_, branchAsset_);
  }

  function _setHubAssetFactory() internal {
    vm.prank(owner);
    assetManager.setHubAssetFactory(address(hubAssetFactory));
  }

  function _setHubAssetInstance(address hubAsset_, bool isInstance) internal {
    hubAssetFactory.setRet(abi.encodeCall(IBeaconBase.isInstance, (hubAsset_)), false, abi.encode(isInstance));
  }

  function _setMatrixVaultFactory() internal {
    vm.prank(owner);
    assetManager.setMatrixVaultFactory(address(matrixVaultFactory));
  }

  function _setMatrixVaultInstance(address matrixVault_, bool isInstance) internal {
    matrixVaultFactory.setRet(abi.encodeCall(IBeaconBase.isInstance, (matrixVault_)), false, abi.encode(isInstance));
  }

  function _setEOLVaultFactory() internal {
    vm.prank(owner);
    assetManager.setEOLVaultFactory(address(eolVaultFactory));
  }

  function _setEOLVaultInstance(address eolVault_, bool isInstance) internal {
    eolVaultFactory.setRet(abi.encodeCall(IBeaconBase.isInstance, (eolVault_)), false, abi.encode(isInstance));
  }
}
