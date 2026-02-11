// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { MitosisVault, AssetAction } from '../../src/branch/MitosisVault.sol';
import { IMitosisVault } from '../../src/interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultEntrypoint } from '../../src/interfaces/branch/IMitosisVaultEntrypoint.sol';
import { IMitosisVaultVLF, VLFAction } from '../../src/interfaces/branch/IMitosisVaultVLF.sol';
import { StdError } from '../../src/lib/StdError.sol';
import { MockERC20Snapshots } from '../mock/MockERC20Snapshots.t.sol';
import { MockMitosisVaultEntrypoint } from '../mock/MockMitosisVaultEntrypoint.t.sol';
import { MockVLFStrategyExecutor } from '../mock/MockVLFStrategyExecutor.t.sol';
import { Toolkit } from '../util/Toolkit.sol';

contract NonReceiveable {
  receive() external payable {
    revert('hehe');
  }
}

contract MitosisVaultTest is Toolkit {
  MitosisVault internal _mitosisVault;
  MockMitosisVaultEntrypoint internal _mitosisVaultEntrypoint;
  MockERC20Snapshots internal _token;
  MockVLFStrategyExecutor internal _vlfStrategyExecutor;

  address immutable owner = makeAddr('owner');
  address immutable liquidityManager = makeAddr('liquidityManager');
  address immutable mitosis = makeAddr('mitosis');
  address immutable hubVLFVault = makeAddr('hubVLFVault');

  function setUp() public {
    _mitosisVault = MitosisVault(
      payable(
        new ERC1967Proxy(
          address(new MitosisVault()), //
          abi.encodeCall(MitosisVault.initialize, (owner))
        )
      )
    );

    _mitosisVaultEntrypoint = new MockMitosisVaultEntrypoint();

    _token = new MockERC20Snapshots();
    _token.initialize('Token', 'TKN');

    _vlfStrategyExecutor = new MockVLFStrategyExecutor(_mitosisVault, _token, hubVLFVault);

    vm.startPrank(owner);
    _mitosisVault.grantRole(_mitosisVault.LIQUIDITY_MANAGER_ROLE(), liquidityManager);
    _mitosisVault.setEntrypoint(address(_mitosisVaultEntrypoint));
    vm.stopPrank();
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

  function test_deposit(uint256 amount) public {
    vm.assume(0 < amount && amount <= type(uint64).max);

    address user1 = makeAddr('user1');
    _token.mint(user1, amount);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(liquidityManager);
    _mitosisVault.setCap(address(_token), type(uint64).max);

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    // set quote deposit gas to 1 ether
    _mitosisVaultEntrypoint.setGas(_mitosisVaultEntrypoint.deposit.selector, 1 ether);
    _mitosisVaultEntrypoint.setGas(_mitosisVaultEntrypoint.quoteDeposit.selector, 1 ether);

    vm.deal(user1, 100 ether);
    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), amount);
    _mitosisVault.deposit{ value: 10 ether }(address(_token), user1, amount);

    vm.stopPrank();

    assertEq(user1.balance, 99 ether); // returned 9 ether
    assertEq(_token.balanceOf(user1), 0);
    assertEq(_token.balanceOf(address(_mitosisVault)), amount);
    assertEq(_mitosisVault.maxCap(address(_token)), type(uint64).max);
    assertEq(_mitosisVault.availableCap(address(_token)), type(uint64).max - amount);
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

  function test_depositWithSupplyVLF(uint256 amount) public {
    vm.assume(0 < amount && amount <= type(uint64).max);

    address user1 = makeAddr('user1');

    _token.mint(user1, amount);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(liquidityManager);
    _mitosisVault.setCap(address(_token), type(uint64).max);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), amount);
    _mitosisVault.depositWithSupplyVLF(address(_token), user1, hubVLFVault, amount);

    vm.stopPrank();

    assertEq(_token.balanceOf(user1), 0);
    assertEq(_token.balanceOf(address(_mitosisVault)), amount);
    assertEq(_mitosisVault.maxCap(address(_token)), type(uint64).max);
    assertEq(_mitosisVault.availableCap(address(_token)), type(uint64).max - amount);
  }

  function test_depositWithSupplyVLF_AssetNotInitialized() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errAssetNotInitialized(address(_token)));
    _mitosisVault.depositWithSupplyVLF(address(_token), user1, hubVLFVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyVLF_AssetHalted() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Halted.selector);
    _mitosisVault.depositWithSupplyVLF(address(_token), user1, hubVLFVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyVLF_VLFNotInitialized() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(liquidityManager);
    _mitosisVault.setCap(address(_token), type(uint128).max); // set cap to infinite (temp)

    // vm.prank(address(_mitosisVaultEntrypoint));
    // _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errVLFNotInitialized(hubVLFVault));
    _mitosisVault.depositWithSupplyVLF(address(_token), user1, hubVLFVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyVLF_ZeroAddress() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errZeroToAddress());
    _mitosisVault.depositWithSupplyVLF(address(_token), address(0), hubVLFVault, 100 ether);

    vm.stopPrank();
  }

  function test_depositWithSupplyVLF_ZeroAmount() public {
    address user1 = makeAddr('user1');

    _token.mint(user1, 100 ether);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    vm.startPrank(user1);

    _token.approve(address(_mitosisVault), 0);

    vm.expectRevert(StdError.ZeroAmount.selector);
    _mitosisVault.depositWithSupplyVLF(address(_token), user1, hubVLFVault, 0);

    vm.stopPrank();
  }

  function test_withdraw(uint256 amount) public {
    test_deposit(amount); // (owner) - - - deposit 100 ETH - - -> (_mitosisVault)
    assertEq(_token.balanceOf(address(_mitosisVault)), amount);

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.withdraw(address(_token), address(1), amount);

    assertEq(_token.balanceOf(address(1)), amount);
    assertEq(_token.balanceOf(address(_mitosisVault)), 0);
    assertEq(_mitosisVault.maxCap(address(_token)), type(uint64).max);
    assertEq(_mitosisVault.availableCap(address(_token)), type(uint64).max);
  }

  function test_withdraw_Unauthorized(uint256 amount) public {
    test_deposit(amount);
    assertEq(_token.balanceOf(address(_mitosisVault)), amount);

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.withdraw(address(_token), address(1), amount);
  }

  function test_withdraw_AssetNotInitialized(uint256 amount) public {
    test_deposit(amount);
    assertEq(_token.balanceOf(address(_mitosisVault)), amount);

    vm.startPrank(address(_mitosisVaultEntrypoint));

    address myToken = address(10);

    vm.expectRevert(_errAssetNotInitialized(myToken));
    _mitosisVault.withdraw(myToken, address(1), amount);

    vm.stopPrank();
  }

  function test_withdraw_NotEnoughBalance(uint256 amount) public {
    test_deposit(amount);
    assertEq(_token.balanceOf(address(_mitosisVault)), amount);

    vm.startPrank(address(_mitosisVaultEntrypoint));

    vm.expectRevert();
    _mitosisVault.withdraw(address(_token), address(1), amount + 1);

    vm.stopPrank();
  }

  function test_initializeVLF() public {
    assertFalse(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.startPrank(address(_mitosisVaultEntrypoint));

    _mitosisVault.initializeAsset(address(_token));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.stopPrank();

    assertTrue(_mitosisVault.isAssetInitialized(address(_token)));
  }

  function test_initializeVLF_Unauthorized() public {
    assertFalse(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));
  }

  function test_initializeVLF_VLFAlreadyInitialized() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.startPrank(address(_mitosisVaultEntrypoint));

    vm.expectRevert(_errVLFAlreadyInitialized(hubVLFVault));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.stopPrank();
  }

  function test_initializeVLF_AssetNotInitialized() public {
    assertFalse(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.startPrank(address(_mitosisVaultEntrypoint));

    // _mitosisVault.initializeAsset(address(_token));
    vm.expectRevert(_errAssetNotInitialized(address(_token)));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.stopPrank();
  }

  function test_allocateVLF() public {
    vm.startPrank(address(_mitosisVaultEntrypoint));

    _mitosisVault.initializeAsset(address(_token));
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    _mitosisVault.allocateVLF(hubVLFVault, 100 ether);

    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);

    vm.stopPrank();
  }

  function test_allocateVLF_Unauthorized() public {
    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.initializeVLF(hubVLFVault, address(_token));
  }

  function test_allocateVLF_VLFNotInitialized() public {
    vm.startPrank(address(_mitosisVaultEntrypoint));

    _mitosisVault.initializeAsset(address(_token));

    // _mitosisVault.initializeVLF(hubVLFVault, address(_token));

    vm.expectRevert(_errVLFNotInitialized(hubVLFVault));
    _mitosisVault.allocateVLF(hubVLFVault, 100 ether);

    vm.stopPrank();
  }

  function test_deallocateVLF() public {
    test_allocateVLF();
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.prank(address(_vlfStrategyExecutor));
    _mitosisVault.deallocateVLF(hubVLFVault, 10 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 90 ether);

    vm.prank(address(_vlfStrategyExecutor));
    _mitosisVault.deallocateVLF(hubVLFVault, 90 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 0 ether);
  }

  function test_deallocateVLF_Unauthorized() public {
    test_allocateVLF();
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.deallocateVLF(hubVLFVault, 10 ether);
  }

  function test_deallocateVLF_InsufficientVLF() public {
    test_allocateVLF();
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.expectRevert();
    _mitosisVault.deallocateVLF(hubVLFVault, 101 ether);
  }

  function test_fetchVLF() public {
    test_allocateVLF();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.startPrank(address(_vlfStrategyExecutor));
    _mitosisVault.fetchVLF(hubVLFVault, 10 ether);
    assertEq(_token.balanceOf(address(_vlfStrategyExecutor)), 10 ether);

    _mitosisVault.fetchVLF(hubVLFVault, 90 ether);
    assertEq(_token.balanceOf(address(_vlfStrategyExecutor)), 100 ether);

    vm.stopPrank();
  }

  function test_fetchVLF_VLFNotInitialized() public {
    // No occurrence case until methods like deinitializeVLF are added.
  }

  function test_fetchVLF_Unauthorized() public {
    test_allocateVLF();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.fetchVLF(hubVLFVault, 10 ether);
  }

  function test_fetchVLF_AssetHalted() public {
    test_allocateVLF();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.prank(owner);

    _mitosisVault.haltVLF(hubVLFVault, VLFAction.FetchVLF);

    vm.startPrank(address(_vlfStrategyExecutor));

    vm.expectRevert(StdError.Halted.selector);
    _mitosisVault.fetchVLF(hubVLFVault, 10 ether);

    vm.stopPrank();
  }

  function test_fetchVLF_InsufficientVLF() public {
    test_allocateVLF();
    _token.mint(address(_mitosisVault), 100 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.startPrank(address(_vlfStrategyExecutor));

    vm.expectRevert();
    _mitosisVault.fetchVLF(hubVLFVault, 101 ether);

    vm.stopPrank();
  }

  function test_returnVLF() public {
    test_fetchVLF();
    assertEq(_token.balanceOf(address(_vlfStrategyExecutor)), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 0);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 0);

    vm.startPrank(address(_vlfStrategyExecutor));

    _token.approve(address(_mitosisVault), 100 ether);
    _mitosisVault.returnVLF(hubVLFVault, 100 ether);

    assertEq(_token.balanceOf(address(_mitosisVault)), 100 ether);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 100 ether);

    vm.stopPrank();
  }

  function test_returnVLF_VLFNotInitialized() public {
    // No occurrence case until methods like deinitializeVLF are added.
  }

  function test_returnVLF_Unauthorized() public {
    test_fetchVLF();
    assertEq(_token.balanceOf(address(_vlfStrategyExecutor)), 100 ether);
    assertEq(_token.balanceOf(address(_mitosisVault)), 0);
    assertEq(_mitosisVault.availableVLF(hubVLFVault), 0);

    vm.prank(address(_vlfStrategyExecutor));
    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.returnVLF(hubVLFVault, 100 ether);
  }

  function test_settleVLFYield() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.prank(address(_vlfStrategyExecutor));
    _mitosisVault.settleVLFYield(hubVLFVault, 100 ether);
  }

  function test_settleVLFYield_VLFNotInitialized() public {
    // No occurrence case until methods like deinitializeVLF are added.
  }

  function test_settleVLFYield_Unauthorized() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.settleVLFYield(hubVLFVault, 100 ether);
  }

  function test_settleVLFLoss() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.prank(address(_vlfStrategyExecutor));
    _mitosisVault.settleVLFLoss(hubVLFVault, 100 ether);
  }

  function test_settleVLFLoss_VLFNotInitialized() public {
    // No occurrence case until methods like deinitializeVLF are added.
  }

  function test_settleVLFLoss_Unauthorized() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.settleVLFLoss(hubVLFVault, 100 ether);
  }

  function test_settleVLFExtraRewards() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    MockERC20Snapshots reward = new MockERC20Snapshots();
    reward.initialize('Reward', 'REWARD');

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(reward));

    vm.startPrank(address(_vlfStrategyExecutor));

    reward.mint(address(_vlfStrategyExecutor), 100 ether);
    reward.approve(address(_mitosisVault), 100 ether);

    _mitosisVault.settleVLFExtraRewards(hubVLFVault, address(reward), 100 ether);

    vm.stopPrank();
  }

  function test_settleVLFExtraRewards_VLFNotInitialized() public {
    // No occurrence case until methods like deinitializeVLF are added.
  }

  function test_settleVLFExtraRewards_Unauthorized() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    MockERC20Snapshots reward = new MockERC20Snapshots();
    reward.initialize('Reward', 'REWARD');

    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(reward));

    reward.mint(address(_vlfStrategyExecutor), 100 ether);

    vm.prank(address(_vlfStrategyExecutor));
    reward.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(StdError.Unauthorized.selector);
    _mitosisVault.settleVLFExtraRewards(hubVLFVault, address(reward), 100 ether);
  }

  function test_settleVLFExtraRewards_AssetNotInitialized() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    MockERC20Snapshots reward = new MockERC20Snapshots();
    reward.initialize('Reward', 'REWARD');

    // vm.prank(address(_mitosisVaultEntrypoint));
    // _mitosisVault.initializeAsset(address(reward));

    vm.startPrank(address(_vlfStrategyExecutor));

    reward.mint(address(_vlfStrategyExecutor), 100 ether);
    reward.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errAssetNotInitialized(address(reward)));
    _mitosisVault.settleVLFExtraRewards(hubVLFVault, address(reward), 100 ether);

    vm.stopPrank();
  }

  function test_settleVLFExtraRewards_InvalidRewardAddress() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.startPrank(address(_vlfStrategyExecutor));

    _token.mint(address(_vlfStrategyExecutor), 100 ether);
    _token.approve(address(_mitosisVault), 100 ether);

    vm.expectRevert(_errInvalidAddress('reward'));
    _mitosisVault.settleVLFExtraRewards(hubVLFVault, address(_token), 100 ether);

    vm.stopPrank();
  }

  function test_setEntrypoint_Unauthorized() public {
    vm.expectRevert();
    _mitosisVault.setEntrypoint(address(0));
  }

  function test_setVLFStrategyExecutor() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));
  }

  function test_setVLFStrategyExecutor_VLFNotInitialized() public {
    vm.startPrank(owner);

    vm.expectRevert(_errVLFNotInitialized(hubVLFVault));
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    vm.stopPrank();
  }

  function test_setVLFStrategyExecutor_VLFStrategyExecutorNotDrained() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(_vlfStrategyExecutor));

    _token.mint(address(_vlfStrategyExecutor), 100 ether);
    assertTrue(_vlfStrategyExecutor.totalBalance() > 0);

    MockVLFStrategyExecutor newVLFStrategyExecutor = new MockVLFStrategyExecutor(_mitosisVault, _token, hubVLFVault);

    vm.startPrank(owner);

    vm.expectRevert(_errVLFStrategyExecutorNotDraind(hubVLFVault, address(_vlfStrategyExecutor)));
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(newVLFStrategyExecutor));

    vm.stopPrank();

    vm.prank(address(_vlfStrategyExecutor));
    _token.transfer(address(1), 100 ether);

    assertEq(_vlfStrategyExecutor.totalBalance(), 0);

    vm.prank(owner);
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(newVLFStrategyExecutor));

    assertEq(_mitosisVault.vlfStrategyExecutor(hubVLFVault), address(newVLFStrategyExecutor));
  }

  function test_setVLFStrategyExecutor_InvalidVaultAddress() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    MockVLFStrategyExecutor newVLFStrategyExecutor =
      new MockVLFStrategyExecutor(IMitosisVault(address(0)), _token, hubVLFVault);

    vm.startPrank(owner);

    vm.expectRevert(_errInvalidAddress('VLFStrategyExecutor.vault'));
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(newVLFStrategyExecutor));

    vm.stopPrank();
  }

  function test_setVLFStrategyExecutor_InvalidAssetAddress() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    MockVLFStrategyExecutor newVLFStrategyExecutor =
      new MockVLFStrategyExecutor(_mitosisVault, IERC20(address(0)), hubVLFVault);

    vm.startPrank(owner);

    vm.expectRevert(_errInvalidAddress('VLFStrategyExecutor.asset'));
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(newVLFStrategyExecutor));

    vm.stopPrank();
  }

  function test_setVLFStrategyExecutor_InvalidhubVLFVault() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    MockVLFStrategyExecutor newVLFStrategyExecutor;
    newVLFStrategyExecutor = new MockVLFStrategyExecutor(_mitosisVault, _token, address(0));

    vm.startPrank(owner);

    vm.expectRevert();
    _mitosisVault.setVLFStrategyExecutor(hubVLFVault, address(newVLFStrategyExecutor));

    newVLFStrategyExecutor = new MockVLFStrategyExecutor(_mitosisVault, _token, hubVLFVault);

    vm.expectRevert();
    _mitosisVault.setVLFStrategyExecutor(address(0), address(newVLFStrategyExecutor));

    vm.stopPrank();
  }

  function test_isVLFActionHalted() public {
    test_initializeVLF();
    assertTrue(_mitosisVault.isVLFInitialized(hubVLFVault));

    assertFalse(_mitosisVault.isVLFActionHalted(hubVLFVault, VLFAction.FetchVLF)); // default to not halted

    vm.prank(owner);

    _mitosisVault.haltVLF(hubVLFVault, VLFAction.FetchVLF);

    assertTrue(_mitosisVault.isVLFActionHalted(hubVLFVault, VLFAction.FetchVLF));
  }

  function test_isAssetActionHalted() public {
    test_initializeAsset();
    assertTrue(_mitosisVault.isAssetInitialized(address(_token)));

    assertTrue(_mitosisVault.isAssetActionHalted(address(_token), AssetAction.Deposit)); // default to halted

    vm.prank(owner);
    _mitosisVault.resumeAsset(address(_token), AssetAction.Deposit);

    assertFalse(_mitosisVault.isAssetActionHalted(address(_token), AssetAction.Deposit));
  }

  function test_setCap(uint256 amount) public {
    vm.assume(2 < amount);
    test_deposit(amount);

    vm.prank(liquidityManager);
    _mitosisVault.setCap(address(_token), type(uint128).max);

    assertEq(_mitosisVault.maxCap(address(_token)), type(uint128).max);
    assertEq(_mitosisVault.availableCap(address(_token)), type(uint128).max - amount);

    vm.prank(liquidityManager);
    _mitosisVault.setCap(address(_token), amount - 1);

    assertEq(_mitosisVault.maxCap(address(_token)), amount - 1);
    assertEq(_mitosisVault.availableCap(address(_token)), 0);
  }

  function test_setCap_Unauthorized() public {
    vm.prank(address(_mitosisVaultEntrypoint));
    _mitosisVault.initializeAsset(address(_token));

    address unauthorizedUser = makeAddr('unauthorizedUser');

    vm.expectRevert(_errAccessControlUnauthorized(unauthorizedUser, _mitosisVault.LIQUIDITY_MANAGER_ROLE()));
    vm.prank(unauthorizedUser);
    _mitosisVault.setCap(address(_token), 100 ether);

    // Owner also cannot call setCap without LIQUIDITY_MANAGER_ROLE
    vm.expectRevert(_errAccessControlUnauthorized(owner, _mitosisVault.LIQUIDITY_MANAGER_ROLE()));
    vm.prank(owner);
    _mitosisVault.setCap(address(_token), 100 ether);
  }

  function _errAssetAlreadyInitialized(address asset) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMitosisVault.IMitosisVault__AssetAlreadyInitialized.selector, asset);
  }

  function _errAssetNotInitialized(address asset) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMitosisVault.IMitosisVault__AssetNotInitialized.selector, asset);
  }

  function _errVLFAlreadyInitialized(address _hubVLFVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMitosisVaultVLF.IMitosisVaultVLF__VLFAlreadyInitialized.selector, _hubVLFVault);
  }

  function _errVLFNotInitialized(address _hubVLFVault) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IMitosisVaultVLF.IMitosisVaultVLF__VLFNotInitialized.selector, _hubVLFVault);
  }

  function _errVLFStrategyExecutorNotDraind(address _hubVLFVault, address vlfStrategyExecutor_)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodeWithSelector(
      IMitosisVaultVLF.IMitosisVaultVLF__StrategyExecutorNotDrained.selector, _hubVLFVault, vlfStrategyExecutor_
    );
  }
}
