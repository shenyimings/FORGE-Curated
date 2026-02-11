// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ERC4626 } from '@solady/tokens/ERC4626.sol';
import { WETH } from '@solady/tokens/WETH.sol';

import { Ownable } from '@oz/access/Ownable.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { BeaconProxy } from '@oz/proxy/beacon/BeaconProxy.sol';
import { IBeacon } from '@oz/proxy/beacon/IBeacon.sol';

import { VLFVaultBasic } from '../../../src/hub/vlf/VLFVaultBasic.sol';
import { VLFVaultCapped } from '../../../src/hub/vlf/VLFVaultCapped.sol';
import { IAssetManager } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { IAssetManagerStorageV1 } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { StdError } from '../../../src/lib/StdError.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract VLFVaultBaseTest is IBeacon, Toolkit {
  address owner = makeAddr('owner');
  address liquidityManager = makeAddr('liquidityManager');
  address user = makeAddr('user');
  address assetManager = _emptyContract();
  address reclaimQueue = _emptyContract();

  WETH weth;

  VLFVaultBasic basicImpl;
  VLFVaultCapped cappedImpl;
  address private defaultImpl;

  VLFVaultBasic basic;
  VLFVaultCapped capped;

  function setUp() public virtual {
    weth = new WETH();

    basicImpl = new VLFVaultBasic();
    cappedImpl = new VLFVaultCapped();

    vm.mockCall(
      address(assetManager),
      abi.encodeWithSelector(IAssetManagerStorageV1.reclaimQueue.selector),
      abi.encode(reclaimQueue)
    );

    vm.mockCall(address(assetManager), abi.encodeWithSelector(Ownable.owner.selector), abi.encode(owner));

    vm.mockCall(
      address(assetManager),
      abi.encodeWithSelector(IAssetManager.isLiquidityManager.selector, liquidityManager),
      abi.encode(true)
    );
    vm.mockCall(
      address(assetManager), abi.encodeWithSelector(IAssetManager.isLiquidityManager.selector, owner), abi.encode(false)
    );
    vm.mockCall(
      address(assetManager), abi.encodeWithSelector(IAssetManager.isLiquidityManager.selector, user), abi.encode(false)
    );

    defaultImpl = address(basicImpl);
    basic = VLFVaultBasic(
      address(
        new BeaconProxy(
          address(this),
          abi.encodeCall(
            VLFVaultBasic.initialize, //
            (assetManager, IERC20Metadata(address(weth)), 'B', 'B')
          )
        )
      )
    );

    defaultImpl = address(cappedImpl);
    capped = VLFVaultCapped(
      address(
        new BeaconProxy(
          address(this),
          abi.encodeCall(
            VLFVaultCapped.initialize, //
            (assetManager, IERC20Metadata(address(weth)), 'C', 'C')
          )
        )
      )
    );

    defaultImpl = address(0);
  }

  function implementation() public view override returns (address) {
    if (msg.sender == address(basic)) return address(basicImpl);
    if (msg.sender == address(capped)) return address(cappedImpl);
    if (defaultImpl != address(0)) return defaultImpl;
    revert('unauthorized');
  }
}

contract VLFVaultBasicTest is VLFVaultBaseTest {
  function test_initialize() public view {
    assertEq(basic.asset(), address(weth));
    assertEq(basic.name(), 'B');
    assertEq(basic.symbol(), 'B');
    assertEq(basic.decimals(), 18 + 6);

    assertEq(basic.assetManager(), assetManager);
    assertEq(basic.reclaimQueue(), reclaimQueue);

    assertEq(_erc1967Beacon(address(basic)), address(this));
  }

  function test_deposit(uint256 amount) public {
    vm.assume(0 < amount && amount < type(uint64).max);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(basic), amount);
    basic.deposit(amount, user);

    vm.stopPrank();

    assertEq(basic.balanceOf(user), amount * 1e6, 'balance');
    assertEq(basic.totalAssets(), amount, 'totalAssets');
    assertEq(basic.totalSupply(), amount * 1e6, 'totalSupply');
    assertEq(basic.convertToShares(amount), amount * 1e6, 'convertToShares');
    assertEq(basic.convertToAssets(amount * 1e6), amount, 'convertToAssets');
  }

  function test_mint(uint256 amount) public {
    vm.assume(0 < amount && amount < type(uint64).max);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(basic), amount);
    basic.mint(amount * 1e6, user);

    vm.stopPrank();

    assertEq(basic.balanceOf(user), amount * 1e6, 'balance');
    assertEq(basic.totalAssets(), amount, 'totalAssets');
    assertEq(basic.totalSupply(), amount * 1e6, 'totalSupply');
    assertEq(basic.convertToShares(amount), amount * 1e6, 'convertToShares');
    assertEq(basic.convertToAssets(amount * 1e6), amount, 'convertToAssets');
  }

  function test_withdraw(uint256 amount) public {
    test_deposit(amount);

    vm.prank(user);
    basic.approve(reclaimQueue, amount * 1e6);

    vm.prank(reclaimQueue);
    basic.withdraw(amount, user, user);

    assertEq(weth.balanceOf(user), amount, 'balance');
    assertEq(basic.balanceOf(user), 0, 'balance');
    assertEq(basic.totalAssets(), 0, 'totalAssets');
    assertEq(basic.totalSupply(), 0, 'totalSupply');
  }

  function test_withdraw_revertsIfUnauthorized(uint256 amount) public {
    test_deposit(amount);

    vm.prank(user);
    vm.expectRevert(StdError.Unauthorized.selector);
    basic.withdraw(amount, user, user);
  }

  function test_redeem(uint256 amount) public {
    test_deposit(amount);

    vm.prank(user);
    basic.approve(reclaimQueue, amount * 1e6);

    vm.prank(reclaimQueue);
    basic.redeem(amount * 1e6, user, user);

    assertEq(weth.balanceOf(user), amount, 'balance');
    assertEq(basic.balanceOf(user), 0, 'balance');
    assertEq(basic.totalAssets(), 0, 'totalAssets');
    assertEq(basic.totalSupply(), 0, 'totalSupply');
  }

  function test_redeem_revertsIfUnauthorized(uint256 amount) public {
    test_deposit(amount);

    vm.prank(user);
    vm.expectRevert(StdError.Unauthorized.selector);
    basic.redeem(amount * 1e6, user, user);
  }
}

contract VLFVaultCappedTest is VLFVaultBaseTest {
  function setUp() public override {
    super.setUp();

    // Initialize soft cap as disabled by default
    vm.prank(liquidityManager);
    capped.setSoftCap(type(uint256).max);
  }

  // ============================ NOTE: BASIC & HARD CAP TESTS ============================ //

  function test_initialize() public view {
    assertEq(capped.asset(), address(weth));
    assertEq(capped.name(), 'C');
    assertEq(capped.symbol(), 'C');
    assertEq(capped.decimals(), 18 + 6);

    assertEq(capped.assetManager(), assetManager);
    assertEq(capped.reclaimQueue(), reclaimQueue);

    assertEq(_erc1967Beacon(address(capped)), address(this));
  }

  function test_setCap(uint256 amount) public {
    assertEq(capped.loadCap(), 0);

    vm.prank(liquidityManager);
    capped.setCap(amount);

    assertEq(capped.loadCap(), amount);
  }

  function test_setCap_revertsIfUnauthorized(uint256 amount) public {
    vm.prank(owner);
    vm.expectRevert(StdError.Unauthorized.selector);
    capped.setCap(amount);
  }

  function test_deposit(uint256 cap, uint256 amount) public {
    vm.assume(0 < amount && amount < type(uint64).max);
    vm.assume(amount <= cap);

    vm.prank(liquidityManager);
    capped.setCap(cap);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(capped), amount);
    capped.deposit(amount, user);

    vm.stopPrank();
  }

  function test_deposit_revertsIfCapExceeded(uint256 cap, uint256 amount) public {
    vm.assume(0 < amount && amount < type(uint64).max);
    vm.assume(cap < amount);

    vm.prank(liquidityManager);
    capped.setCap(cap);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(capped), amount);

    vm.expectRevert(ERC4626.DepositMoreThanMax.selector);
    capped.deposit(amount, user);

    vm.stopPrank();
  }

  function test_mint(uint256 cap, uint256 amount) public {
    vm.assume(0 < amount && amount < type(uint64).max);
    vm.assume(amount <= cap && cap < type(uint64).max); // TODO:

    vm.prank(liquidityManager);
    capped.setCap(cap);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(capped), amount);
    capped.mint(amount * 1e6, user);

    vm.stopPrank();
  }

  function test_mint_revertsIfCapExceeded(uint256 cap, uint256 amount) public {
    vm.assume(0 < amount && amount < type(uint64).max);
    vm.assume(amount > cap);

    vm.prank(liquidityManager);
    capped.setCap(cap);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(capped), amount);

    vm.expectRevert(ERC4626.MintMoreThanMax.selector);
    capped.mint(amount * 1e6, user);

    vm.stopPrank();
  }

  function test_withdraw(uint256 cap, uint256 amount) public {
    test_deposit(cap, amount);

    vm.prank(user);
    capped.approve(reclaimQueue, amount * 1e6);

    vm.prank(reclaimQueue);
    capped.withdraw(amount, user, user);
  }

  function test_withdraw_revertsIfUnauthorized(uint256 cap, uint256 amount) public {
    test_deposit(cap, amount);

    vm.prank(user);
    vm.expectRevert(StdError.Unauthorized.selector);
    capped.withdraw(amount, user, user);
  }

  function test_redeem(uint256 cap, uint256 amount) public {
    test_deposit(cap, amount);

    vm.prank(user);
    capped.approve(reclaimQueue, amount * 1e6);

    vm.prank(reclaimQueue);
    capped.redeem(amount * 1e6, user, user);
  }

  function test_redeem_revertsIfUnauthorized(uint256 cap, uint256 amount) public {
    test_deposit(cap, amount);

    vm.prank(user);
    vm.expectRevert(StdError.Unauthorized.selector);
    capped.redeem(amount * 1e6, user, user);
  }

  // ============================ NOTE: SOFT CAP &PREFERRED CHAIN TESTS ============================ //

  function test_setSoftCap(uint256 amount) public {
    vm.prank(liquidityManager);
    capped.setSoftCap(amount);

    assertEq(capped.loadSoftCap(), amount);
  }

  function test_setSoftCap_revertsIfUnauthorized(uint256 amount) public {
    vm.prank(user);
    vm.expectRevert(StdError.Unauthorized.selector);
    capped.setSoftCap(amount);
  }

  function test_addPreferredChainId(uint256 chainId) public {
    assertEq(capped.isPreferredChain(chainId), false);

    vm.prank(liquidityManager);
    capped.addPreferredChainId(chainId);

    assertEq(capped.isPreferredChain(chainId), true);

    uint256[] memory chainIds = capped.preferredChainIds();
    assertEq(chainIds.length, 1);
    assertEq(chainIds[0], chainId);
  }

  function test_addPreferredChainId_revertsIfUnauthorized(uint256 chainId) public {
    vm.prank(user);
    vm.expectRevert(StdError.Unauthorized.selector);
    capped.addPreferredChainId(chainId);
  }

  function test_removePreferredChainId(uint256 chainId) public {
    // Add first
    vm.prank(liquidityManager);
    capped.addPreferredChainId(chainId);
    assertEq(capped.isPreferredChain(chainId), true);

    // Remove
    vm.prank(liquidityManager);
    capped.removePreferredChainId(chainId);
    assertEq(capped.isPreferredChain(chainId), false);

    uint256[] memory chainIds = capped.preferredChainIds();
    assertEq(chainIds.length, 0);
  }

  function test_preferredChainIds_multiple() public {
    uint256 chainId1 = 8453; // Base
    uint256 chainId2 = 42161; // Arbitrum
    uint256 chainId3 = 1; // Ethereum

    vm.startPrank(liquidityManager);
    capped.addPreferredChainId(chainId1);
    capped.addPreferredChainId(chainId2);
    capped.addPreferredChainId(chainId3);
    vm.stopPrank();

    uint256[] memory chainIds = capped.preferredChainIds();
    assertEq(chainIds.length, 3);

    assertEq(capped.isPreferredChain(chainId1), true);
    assertEq(capped.isPreferredChain(chainId2), true);
    assertEq(capped.isPreferredChain(chainId3), true);
    assertEq(capped.isPreferredChain(999), false); // Non-added chain
  }

  function test_maxDeposit_withSoftCap(uint256 hardCap, uint256 softCap) public {
    vm.assume(softCap < hardCap);

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    vm.stopPrank();

    // When totalAssets = 0, maxDeposit should be softCap (smaller of two)
    assertEq(capped.maxDeposit(user), softCap);
  }

  function test_maxDeposit_softCapDisabled(uint256 hardCap) public {
    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(type(uint256).max); // Disable soft cap
    vm.stopPrank();

    // When softCap is max, should return hardCap limit
    assertEq(capped.maxDeposit(user), hardCap);
  }

  function test_maxDepositFromChainId_preferredChain(uint256 hardCap, uint256 softCap, uint256 chainId) public {
    vm.assume(softCap < hardCap);
    vm.assume(chainId != 9622);

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    capped.addPreferredChainId(chainId);
    vm.stopPrank();

    // Preferred chain should bypass soft cap
    assertEq(capped.maxDepositFromChainId(user, chainId), hardCap);
    // Non-preferred chain should respect soft cap
    assertEq(capped.maxDepositFromChainId(user, 9622), softCap);
  }

  function test_maxDepositFromChainId_nonPreferredChain(uint256 hardCap, uint256 softCap, uint256 chainId) public {
    vm.assume(softCap < hardCap);

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    // Don't add chainId as preferred
    vm.stopPrank();

    // Non-preferred chain should apply soft cap
    assertEq(capped.maxDepositFromChainId(user, chainId), softCap);
  }

  function test_maxDepositFromChainId_withExistingDeposits() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 300 ether;
    uint256 preferredChainId = 8453;
    uint256 nonPreferredChainId = 42161;

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    capped.addPreferredChainId(preferredChainId);
    vm.stopPrank();

    // Make some deposits first
    vm.deal(user, depositAmount);
    vm.startPrank(user);
    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);
    capped.deposit(depositAmount, user);
    vm.stopPrank();

    // Preferred chain: hardCap - totalAssets = 1000 - 300 = 700
    assertEq(capped.maxDepositFromChainId(user, preferredChainId), hardCap - depositAmount);

    // Non-preferred chain: softCap - totalAssets = 500 - 300 = 200
    assertEq(capped.maxDepositFromChainId(user, nonPreferredChainId), softCap - depositAmount);
  }

  function test_maxDepositFromChainId_softCapExceeded() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 600 ether; // Exceeds soft cap
    uint256 preferredChainId = 8453;
    uint256 nonPreferredChainId = 42161;

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    // Don't set soft cap yet, allow deposit first
    capped.addPreferredChainId(preferredChainId);
    vm.stopPrank();

    // Make deposits first (without soft cap restriction)
    vm.deal(user, depositAmount);
    vm.startPrank(user);
    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);
    capped.deposit(depositAmount, user);
    vm.stopPrank();

    // Now set soft cap after deposit (creates "exceeded" condition)
    vm.prank(liquidityManager);
    capped.setSoftCap(softCap);

    // Preferred chain: can still deposit up to hard cap
    assertEq(capped.maxDepositFromChainId(user, preferredChainId), hardCap - depositAmount);

    // Non-preferred chain: soft cap exceeded, should return 0
    assertEq(capped.maxDepositFromChainId(user, nonPreferredChainId), 0);
  }

  function test_deposit_exceedsSoftCap() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 600 ether; // Exceeds soft cap

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    vm.stopPrank();

    vm.deal(user, depositAmount);
    vm.startPrank(user);

    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);

    // Should revert because it exceeds soft cap (which is applied to maxDeposit)
    vm.expectRevert(ERC4626.DepositMoreThanMax.selector);
    capped.deposit(depositAmount, user);

    vm.stopPrank();
  }

  function test_deposit_withinSoftCap() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 400 ether; // Within soft cap

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    vm.stopPrank();

    vm.deal(user, depositAmount);
    vm.startPrank(user);

    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);
    capped.deposit(depositAmount, user);

    vm.stopPrank();

    assertEq(capped.balanceOf(user), depositAmount * 1e6);
    assertEq(capped.totalAssets(), depositAmount);
  }

  function test_depositFromChainId_onlyAssetManager(uint256 amount, uint256 chainId) public {
    vm.assume(0 < amount && amount < type(uint64).max);

    vm.deal(user, amount);
    vm.startPrank(user);

    weth.deposit{ value: amount }();
    weth.approve(address(capped), amount);

    // Should revert because only AssetManager can call depositFromChainId
    vm.expectRevert(StdError.Unauthorized.selector);
    capped.depositFromChainId(amount, user, chainId);

    vm.stopPrank();
  }

  function test_depositFromChainId_preferredChain() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 600 ether; // Exceeds soft cap but should bypass
    uint256 chainId = 8453; // Base

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    capped.addPreferredChainId(chainId);
    vm.stopPrank();

    bool isPreferred = capped.isPreferredChain(chainId);
    assertTrue(isPreferred);

    uint256 maxPreferred = capped.maxDepositFromChainId(user, chainId);
    uint256 maxNonPreferred = capped.maxDepositFromChainId(user, 999); // Different non-preferred chain
    assertEq(maxPreferred, hardCap, 'Preferred chain should allow hard cap');
    assertEq(maxNonPreferred, softCap, 'Non-preferred chain should be limited by soft cap');

    // Prepare assets for AssetManager
    vm.deal(assetManager, depositAmount);
    vm.startPrank(assetManager);
    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);

    // Preferred chain should bypass soft cap
    capped.depositFromChainId(depositAmount, user, chainId);

    vm.stopPrank();

    assertEq(capped.balanceOf(user), depositAmount * 1e6);
    assertEq(capped.totalAssets(), depositAmount);
  }

  function test_depositFromChainId_nonPreferredChain() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 400 ether; // Within soft cap
    uint256 chainId = 42161; // Arbitrum (not preferred)

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    // Don't add chainId as preferred
    vm.stopPrank();

    // Prepare assets for AssetManager
    vm.deal(assetManager, depositAmount);
    vm.startPrank(assetManager);
    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);

    // Non-preferred chain should respect soft cap
    capped.depositFromChainId(depositAmount, user, chainId);

    vm.stopPrank();

    assertEq(capped.balanceOf(user), depositAmount * 1e6);
    assertEq(capped.totalAssets(), depositAmount);
  }

  function test_depositFromChainId_exceedsSoftCap() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 600 ether; // Exceeds soft cap
    uint256 chainId = 42161; // Arbitrum (not preferred)

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    // Don't add chainId as preferred
    vm.stopPrank();

    // Prepare assets for AssetManager
    vm.deal(assetManager, depositAmount);
    vm.startPrank(assetManager);
    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);

    // Should revert because non-preferred chain exceeds soft cap
    vm.expectRevert(abi.encodeWithSignature('DepositMoreThanMax()'));
    capped.depositFromChainId(depositAmount, user, chainId);

    vm.stopPrank();
  }

  function test_depositFromChainId_withinSoftCap() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 depositAmount = 400 ether; // Within soft cap
    uint256 chainId = 42161; // Arbitrum (not preferred)

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    vm.stopPrank();

    // Prepare assets for AssetManager
    vm.deal(assetManager, depositAmount);
    vm.startPrank(assetManager);
    weth.deposit{ value: depositAmount }();
    weth.approve(address(capped), depositAmount);

    // Should succeed because it's within soft cap
    capped.depositFromChainId(depositAmount, user, chainId);

    vm.stopPrank();

    assertEq(capped.balanceOf(user), depositAmount * 1e6);
    assertEq(capped.totalAssets(), depositAmount);
  }

  function test_mint_exceedsSoftCap() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 sharesAmount = 600 ether * 1e6; // Exceeds soft cap (600 ether worth of shares)

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    vm.stopPrank();

    vm.deal(user, 600 ether);
    vm.startPrank(user);

    weth.deposit{ value: 600 ether }();
    weth.approve(address(capped), 600 ether);

    // Should revert because it exceeds soft cap (which is applied to maxMint)
    vm.expectRevert(ERC4626.MintMoreThanMax.selector);
    capped.mint(sharesAmount, user);

    vm.stopPrank();
  }

  function test_mint_withinSoftCap() public {
    uint256 hardCap = 1000 ether;
    uint256 softCap = 500 ether;
    uint256 sharesAmount = 400 ether * 1e6; // Within soft cap (400 ether worth of shares)

    vm.startPrank(liquidityManager);
    capped.setCap(hardCap);
    capped.setSoftCap(softCap);
    vm.stopPrank();

    vm.deal(user, 400 ether);
    vm.startPrank(user);

    weth.deposit{ value: 400 ether }();
    weth.approve(address(capped), 400 ether);
    capped.mint(sharesAmount, user);

    vm.stopPrank();

    assertEq(capped.balanceOf(user), sharesAmount);
    assertEq(capped.totalAssets(), 400 ether);
  }
}
