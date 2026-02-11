// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { MitosisVault, AssetAction } from '../../src/branch/MitosisVault.sol';
import { IMitosisVault } from '../../src/interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../../src/interfaces/branch/IMitosisVaultEntrypoint.sol';
import { IMitosisVaultEOL, EOLAction } from '../../src/interfaces/branch/IMitosisVaultEOL.sol';
import { IMitosisVaultMatrix, MatrixAction } from '../../src/interfaces/branch/IMitosisVaultMatrix.sol';
import { StdError } from '../../src/lib/StdError.sol';
import { MockERC20Snapshots } from '../mock/MockERC20Snapshots.t.sol';
import { MockMatrixStrategyExecutor } from '../mock/MockMatrixStrategyExecutor.t.sol';
import { MockMitosisVaultEntrypoint } from '../mock/MockMitosisVaultEntrypoint.t.sol';
import { Toolkit } from '../util/Toolkit.sol';

contract MitosisVaultTest is Toolkit {
  MitosisVault internal _mitosisVault;
  MockMitosisVaultEntrypoint internal _mitosisVaultEntrypoint;
  MockERC20Snapshots internal _token;
  MockMatrixStrategyExecutor internal _matrixStrategyExecutor;

  address immutable owner = makeAddr('owner');
  address immutable mitosis = makeAddr('mitosis');
  address immutable hubMatrixVault = makeAddr('hubMatrixVault');

  function setUp() public {
    _mitosisVault = MitosisVault(
      payable(new ERC1967Proxy(address(new MitosisVault()), abi.encodeCall(MitosisVault.initialize, (owner))))
    );

    _mitosisVaultEntrypoint = new MockMitosisVaultEntrypoint();

    _token = new MockERC20Snapshots();
    _token.initialize('Token', 'TKN');

    _matrixStrategyExecutor = new MockMatrixStrategyExecutor(_mitosisVault, _token, hubMatrixVault);

    vm.prank(owner);
    _mitosisVault.setEntrypoint(address(_mitosisVaultEntrypoint));
  }

  function test_initializeAsset() public {
    assertFalse(_mitosisVault.isAssetInitialized(address(_token)));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    assertTrue(_mitosisVault.isAssetInitialized(address(_token)));
  }

  function test_initializeAsset_Unauthorized() public {
    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.initializeAsset(address(_token));

    vm.startPrank(owner);
    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.initializeAsset(address(_token));
    vm.stopPrank();
  }

  function test_initializeAsset_AssetAlreadyInitialized() public {
    vm.startPrank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    assertTrue(_mitosisVault.isAssetInitialized(address(_token)));

    vm.expectRevert(_errAssetAlreadyInitialized(address(_token)));
    _mitosisVault.initializeAsset(address(_token));

    vm.stopPrank();
  }

  function test_deposit() public {
    address user1 = makeAddr('user1');
    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(owner);
    _mitosisVault.setCap(address(_token), type(uint128).max); // set cap to infinite (temp)

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);
    _mitosisVault.deposit(address(_token), user1, 100 ether);

    assertEq(_token.balanceOf(user1), 0);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.stopPrank();
  }

  function test_deposit_AssetNotInitialized() public {
    address user1 = makeAddr('user1');
    _token.mint(user1, 100 ether);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errAssetNotInitialized(address(_token)));
    _mitosisVault.deposit(address(_token), user1, 100 ether);

    vm.stopPrank();
  }

  function test_deposit_AssetHalted() public {
    address user1 = makeAddr('user1');
    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Halted.selector);
    _mitosisVault.deposit(address(_token), user1, 100 ether);

    vm.stopPrank();
  }

  function test_deposit_ZeroAddress() public {
    address user1 = makeAddr('user1');
    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errZeroToAddress());
    _mitosisVault.deposit(address(_token), address(0), 100 ether);

    vm.stopPrank();
  }

  function test_deposit_ZeroAmount() public {
    address user1 = makeAddr('user1');
    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 0);

    vm.expectRevert(StdError.ZeroAmount.selector);
    _mitosisVault.deposit(address(_token), user1, 0);

    vm.stopPrank();
  }

  function test_depositWithSupplyMatrix() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(owner);
    _mitosisVault.setCap(address(_token), type(uint128).max); // set cap to infinite (temp)

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);
    _mitosisVault.depositWithSupplyMatrix(address(_token), user1, hubMatrixVault, 100 ether);

    assertEq(_token.balanceOf(user1), 0);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyMatrix_AssetNotInitialized() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errAssetNotInitialized(address(_token)));
    _mitosisVault.depositWithSupplyMatrix(address(_token), user1, hubMatrixVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyMatrix_AssetHalted() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Halted.selector);
    _mitosisVault.depositWithSupplyMatrix(address(_token), user1, hubMatrixVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyMatrix_MatrixNotInitialized() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(owner);
    _mitosisVault.setCap(address(_token), type(uint128).max); // set cap to infinite (temp)

    // vm.prank(address(_mitosisVaultEntrypoint));
    // _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errMatrixNotInitialized(hubMatrixVault));
    _mitosisVault.depositWithSupplyMatrix(address(_token), user1, hubMatrixVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyMatrix_ZeroAddress() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errZeroToAddress());
    _mitosisVault.depositWithSupplyMatrix(address(_token), address(0), hubMatrixVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyMatrix_ZeroAmount() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 0);

    vm.expectRevert(StdError.ZeroAmount.selector);
    _mitosisVault.depositWithSupplyMatrix(address(_token), user1, hubMatrixVault, 0);

    vm.stopPrank();
  }

  function test_withdraw() public {
    test_deposit(); // (owner) - - - deposit 100 ETH - - -> (_mitosisVault)
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.withdraw(address(_token), address(1), 10 ether);

    assertEq(_token.balanceOf(address(1)), 10 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 90 ether);
  }

  function test_withdraw_Unauthorized() public {
    test_deposit();
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.withdraw(address(_token), address(1), 10 ether);
  }

  function test_withdraw_AssetNotInitialized() public {
    test_deposit();
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.startPrank(address(_mitosisVaultEntrypoint));

    address myToken = address(10);

    vm.expectRevert(_errAssetNotInitialized(myToken));
    _mitosisVault.withdraw(myToken, address(1), 10 ether);

    vm.stopPrank();
  }

  function test_withdraw_NotEnoughBalance() public {
    test_deposit();
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.startPrank(address(_mitosisVaultEntrypoint));

    vm.expectRevert();
    _mitosisVault.withdraw(address(_token), address(1), 101 ether);

    vm.stopPrank();
  }

  function test_initializeMatrix() public {
    assertFalse(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.startPrank(address(_mitosisVaultEntrypoint));

    _mitosisVault.initializeAsset(address(_token));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.stopPrank();

    assertTrue(_mitosisVault.isAssetInitialized(address(_token)));
  }

  function test_initializeMatrix_Unauthorized() public {
    assertFalse(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));
  }

  function test_initializeMatrix_MatrixAlreadyInitialized() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.startPrank(address(_mitosisVaultEntrypoint));

    vm.expectRevert(_errMatrixAlreadyInitialized(hubMatrixVault));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.stopPrank();
  }

  function test_initializeMatrix_AssetNotInitialized() public {
    assertFalse(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.startPrank(address(_mitosisVaultEntrypoint));

    // _mitosisVault.initializeAsset(address(_token));
    vm.expectRevert(_errAssetNotInitialized(address(_token)));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.stopPrank();
  }

  function test_allocateMatrix() public {
    vm.startPrank(address(_mitosisVaultEntrypoint));

    _mitosisVault.initializeAsset(address(_token));
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    _mitosisVault.allocateMatrix(hubMatrixVault, 100 ether);

    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);

    vm.stopPrank();
  }

  function test_allocateMatrix_Unauthorized() public {
    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));
  }

  function test_allocateMatrix_MatrixNotInitialized() public {
    vm.startPrank(address(_mitosisVaultEntrypoint));

    _mitosisVault.initializeAsset(address(_token));

    // _mitosisVault.initializeMatrix(hubMatrixVault, address(_token));

    vm.expectRevert(_errMatrixNotInitialized(hubMatrixVault));
    _mitosisVault.allocateMatrix(hubMatrixVault, 100 ether);

    vm.stopPrank();
  }

  function test_deallocateMatrix() public {
    test_allocateMatrix();
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.prank(address(_matrixStrategyExecutor));
    _mitosisVault.deallocateMatrix(hubMatrixVault, 10 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 90 ether);

    vm.prank(address(_matrixStrategyExecutor));
    _mitosisVault.deallocateMatrix(hubMatrixVault, 90 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 0 ether);
  }

  function test_deallocateMatrix_Unauthorized() public {
    test_allocateMatrix();
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.deallocateMatrix(hubMatrixVault, 10 ether);
  }

  function test_deallocateMatrix_InsufficientMatrix() public {
    test_allocateMatrix();
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.expectRevert();
    _mitosisVault.deallocateMatrix(hubMatrixVault, 101 ether);
  }

  function test_fetchMatrix() public {
    test_allocateMatrix();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.startPrank(address(_matrixStrategyExecutor));
    _mitosisVault.fetchMatrix(hubMatrixVault, 10 ether);
    assertEq(_token.balanceOf(address(_matrixStrategyExecutor)), 10 ether);

    _mitosisVault.fetchMatrix(hubMatrixVault, 90 ether);
    assertEq(_token.balanceOf(address(_matrixStrategyExecutor)), 100 ether);

    vm.stopPrank();
  }

  function test_fetchMatrix_MatrixNotInitialized() public {
    // No occurrence case until methods like deinitializeMatrix are added.
  }

  function test_fetchMatrix_Unauthorized() public {
    test_allocateMatrix();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.fetchMatrix(hubMatrixVault, 10 ether);
  }

  function test_fetchMatrix_AssetHalted() public {
    test_allocateMatrix();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.prank(owner);

    _mitosisVault.haltMatrix(hubMatrixVault, MatrixAction.FetchMatrix);

    vm.startPrank(address(_matrixStrategyExecutor));

    vm.expectRevert(StdError.Halted.selector);
    _mitosisVault.fetchMatrix(hubMatrixVault, 10 ether);

    vm.stopPrank();
  }

  function test_fetchMatrix_InsufficientMatrix() public {
    test_allocateMatrix();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.startPrank(address(_matrixStrategyExecutor));

    vm.expectRevert();
    _mitosisVault.fetchMatrix(hubMatrixVault, 101 ether);

    vm.stopPrank();
  }

  function test_returnMatrix() public {
    test_fetchMatrix();
    assertEq(_token.balanceOf(address(_matrixStrategyExecutor)), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 0);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 0);

    vm.startPrank(address(_matrixStrategyExecutor));

    _token.approve(address(_mitosisVault), 100 ether);
    _mitosisVault.returnMatrix(hubMatrixVault, 100 ether);

    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 100 ether);

    vm.stopPrank();
  }

  function test_returnMatrix_MatrixNotInitialized() public {
    // No occurrence case until methods like deinitializeMatrix are added.
  }

  function test_returnMatrix_Unauthorized() public {
    test_fetchMatrix();
    assertEq(_token.balanceOf(address(_matrixStrategyExecutor)), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 0);
    assertEq(_mitosisVault.availableMatrix(hubMatrixVault), 0);

    vm.prank(address(_matrixStrategyExecutor));
    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.returnMatrix(hubMatrixVault, 100 ether);
  }

  function test_settleMatrixYield() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.prank(address(_matrixStrategyExecutor));
    _mitosisVault.settleMatrixYield(hubMatrixVault, 100 ether);
  }

  function test_settleMatrixYield_MatrixNotInitialized() public {
    // No occurrence case until methods like deinitializeMatrix are added.
  }

  function test_settleMatrixYield_Unauthorized() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.settleMatrixYield(hubMatrixVault, 100 ether);
  }

  function test_settleMatrixLoss() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.prank(address(_matrixStrategyExecutor));
    _mitosisVault.settleMatrixLoss(hubMatrixVault, 100 ether);
  }

  function test_settleMatrixLoss_MatrixNotInitialized() public {
    // No occurrence case until methods like deinitializeMatrix are added.
  }

  function test_settleMatrixLoss_Unauthorized() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.settleMatrixLoss(hubMatrixVault, 100 ether);
  }

  function test_settleMatrixExtraRewards() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    MockERC20Snapshots reward = new MockERC20Snapshots();
    reward.initialize('Reward', 'REWARD');

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(reward));

    vm.startPrank(address(_matrixStrategyExecutor));

    reward.mint(address(_matrixStrategyExecutor), 100 ether);
    reward.approve(address(_mitosisVault), 100 ether);

    _mitosisVault.settleMatrixExtraRewards(hubMatrixVault, address(reward), 100 ether);

    vm.stopPrank();
  }

  function test_settleMatrixExtraRewards_MatrixNotInitialized() public {
    // No occurrence case until methods like deinitializeMatrix are added.
  }

  function test_settleMatrixExtraRewards_Unauthorized() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    MockERC20Snapshots reward = new MockERC20Snapshots();
    reward.initialize('Reward', 'REWARD');

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(reward));

    reward.mint(address(_matrixStrategyExecutor), 100 ether);

    vm.prank(address(_matrixStrategyExecutor));
    reward.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.settleMatrixExtraRewards(hubMatrixVault, address(reward), 100 ether);
  }

  function test_settleMatrixExtraRewards_AssetNotInitialized() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    MockERC20Snapshots reward = new MockERC20Snapshots();
    reward.initialize('Reward', 'REWARD');

    // vm.prank(address(_mitosisVaultEntrypoint));
    // _mitosisVault.initializeAsset(address(reward));

    vm.startPrank(address(_matrixStrategyExecutor));

    reward.mint(address(_matrixStrategyExecutor), 100 ether);
    reward.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errAssetNotInitialized(address(reward)));
    _mitosisVault.settleMatrixExtraRewards(hubMatrixVault, address(reward), 100 ether);

    vm.stopPrank();
  }

  function test_settleMatrixExtraRewards_InvalidRewardAddress() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.startPrank(address(_matrixStrategyExecutor));

    _token.mint(address(_matrixStrategyExecutor), 100 ether);
    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errInvalidAddress('reward'));
    _mitosisVault.settleMatrixExtraRewards(hubMatrixVault, address(_token), 100 ether);

    vm.stopPrank();
  }

  function test_setEntrypoint_Unauthorized() public {
    vm.expectRevert();
    _mitosisVault.setEntrypoint(address(0));
  }

  function test_setMatrixStrategyExecutor() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));
  }

  function test_setMatrixStrategyExecutor_MatrixNotInitialized() public {
    vm.startPrank(owner);

    vm.expectRevert(_errMatrixNotInitialized(hubMatrixVault));
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    vm.stopPrank();
  }

  function test_setMatrixStrategyExecutor_MatrixStrategyExecutorNotDrained() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(_matrixStrategyExecutor));

    _token.mint(address(_matrixStrategyExecutor), 100 ether);
    assertTrue(_matrixStrategyExecutor.totalBalance() > 0);

    MockMatrixStrategyExecutor newMatrixStrategyExecutor =
      new MockMatrixStrategyExecutor(_mitosisVault, _token, hubMatrixVault);

    vm.startPrank(owner);

    vm.expectRevert(_errMatrixStrategyExecutorNotDraind(hubMatrixVault, address(_matrixStrategyExecutor)));
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(newMatrixStrategyExecutor));

    vm.stopPrank();

    vm.prank(address(_matrixStrategyExecutor));
    _token.transfer(address(1), 100 ether);

    assertEq(_matrixStrategyExecutor.totalBalance(), 0);

    vm.prank(owner);
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(newMatrixStrategyExecutor));

    assertEq(_mitosisVault.matrixStrategyExecutor(hubMatrixVault), address(newMatrixStrategyExecutor));
  }

  function test_setMatrixStrategyExecutor_InvalidVaultAddress() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    MockMatrixStrategyExecutor newMatrixStrategyExecutor =
      new MockMatrixStrategyExecutor(IMitosisVault(address(0)), _token, hubMatrixVault);

    vm.startPrank(owner);

    vm.expectRevert(_errInvalidAddress('matrixStrategyExecutor.vault'));
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(newMatrixStrategyExecutor));

    vm.stopPrank();
  }

  function test_setMatrixStrategyExecutor_InvalidAssetAddress() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    MockMatrixStrategyExecutor newMatrixStrategyExecutor =
      new MockMatrixStrategyExecutor(_mitosisVault, IERC20(address(0)), hubMatrixVault);

    vm.startPrank(owner);

    vm.expectRevert(_errInvalidAddress('matrixStrategyExecutor.asset'));
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(newMatrixStrategyExecutor));

    vm.stopPrank();
  }

  function test_setMatrixStrategyExecutor_InvalidhubMatrixVault() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    MockMatrixStrategyExecutor newMatrixStrategyExecutor;
    newMatrixStrategyExecutor = new MockMatrixStrategyExecutor(_mitosisVault, _token, address(0));

    vm.startPrank(owner);

    vm.expectRevert();
    _mitosisVault.setMatrixStrategyExecutor(hubMatrixVault, address(newMatrixStrategyExecutor));

    newMatrixStrategyExecutor = new MockMatrixStrategyExecutor(_mitosisVault, _token, hubMatrixVault);

    vm.expectRevert();
    _mitosisVault.setMatrixStrategyExecutor(address(0), address(newMatrixStrategyExecutor));

    vm.stopPrank();
  }

  function test_isMatrixActionHalted() public {
    test_initializeMatrix();
    assertTrue(_mitosisVault.isMatrixInitialized(hubMatrixVault));

    assertFalse(_mitosisVault.isMatrixActionHalted(hubMatrixVault, MatrixAction.FetchMatrix)); // default to not halted

    vm.prank(owner);

    _mitosisVault.haltMatrix(hubMatrixVault, MatrixAction.FetchMatrix);

    assertTrue(_mitosisVault.isMatrixActionHalted(hubMatrixVault, MatrixAction.FetchMatrix));
  }

  function test_isAssetActionHalted() public {
    test_initializeAsset();
    assertTrue(_mitosisVault.isAssetInitialized(address(_token)));

    assertTrue(_mitosisVault.isAssetActionHalted(address(_token), AssetAction.Deposit)); // default to halted

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    assertFalse(_mitosisVault.isAssetActionHalted(address(_token), AssetAction.Deposit));
  }

  function _errAssetAlreadyInitialized(address asset) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMitosisVault.IMitosisVault__AssetAlreadyInitialized.selector, asset);
  }

  function _errAssetNotInitialized(address asset) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMitosisVault.IMitosisVault__AssetNotInitialized.selector, asset);
  }

  function _errMatrixAlreadyInitialized(address _hubMatrixVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      IMitosisVaultMatrix.IMitosisVaultMatrix__MatrixAlreadyInitialized.selector, _hubMatrixVault
    );
  }

  function _errMatrixNotInitialized(address _hubMatrixVault) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(IMitosisVaultMatrix.IMitosisVaultMatrix__MatrixNotInitialized.selector, _hubMatrixVault);
  }

  function _errMatrixStrategyExecutorNotDraind(address _hubMatrixVault, address matrixStrategyExecutor_)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodeWithSelector(
      IMitosisVaultMatrix.IMitosisVaultMatrix__StrategyExecutorNotDrained.selector,
      _hubMatrixVault,
      matrixStrategyExecutor_
    );
  }
}
