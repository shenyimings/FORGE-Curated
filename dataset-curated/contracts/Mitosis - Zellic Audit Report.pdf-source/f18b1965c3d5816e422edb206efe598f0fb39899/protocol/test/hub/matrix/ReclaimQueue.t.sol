// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { IERC4626 } from '@oz/interfaces/IERC4626.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';

import { Test } from '@std/Test.sol';

import { HubAsset } from '../../../src/hub/core/HubAsset.sol';
import { MatrixVaultBasic } from '../../../src/hub/matrix/MatrixVaultBasic.sol';
import { ReclaimQueue } from '../../../src/hub/ReclaimQueue.sol';
import { IAssetManager } from '../../../src/interfaces/hub/core/IAssetManager.sol';
import { IReclaimQueue } from '../../../src/interfaces/hub/matrix/IReclaimQueue.sol';
import { LibMockERC20 } from '../../mock/LibMockERC20.sol';
import { LibMockERC4626 } from '../../mock/LibMockERC4626.sol';
import { SimpleERC4626Vault } from '../../mock/SimpleERC4626Vault.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract ReclaimQueueTestHelper is Test {
  using SafeCast for uint256;

  function makeRequest(uint256 timestamp, uint256 assets, uint256 sharesAcc)
    internal
    pure
    returns (IReclaimQueue.Request memory)
  {
    return IReclaimQueue.Request({
      timestamp: timestamp.toUint48(),
      assets: assets.toUint208(),
      sharesAcc: sharesAcc.toUint208()
    });
  }

  function makeSyncLog(
    uint256 timestamp,
    uint256 reqIdFrom,
    uint256 reqIdTo,
    uint256 sharesAcc,
    uint256 totalSupply,
    uint256 totalAssets
  ) internal pure returns (IReclaimQueue.SyncLog memory) {
    return IReclaimQueue.SyncLog({
      timestamp: timestamp.toUint48(),
      reqIdFrom: reqIdFrom.toUint32(),
      reqIdTo: reqIdTo.toUint32(),
      sharesAcc: sharesAcc.toUint144(),
      totalSupply: totalSupply.toUint128(),
      totalAssets: totalAssets.toUint128()
    });
  }

  function makeSyncResult(
    uint256 logIndex,
    uint256 reqIdFrom,
    uint256 reqIdTo,
    uint256 totalSupply,
    uint256 totalAssets,
    uint256 totalSharesSynced,
    uint256 totalAssetsOnReserve,
    uint256 totalAssetsOnRequest
  ) internal pure returns (IReclaimQueue.SyncResult memory) {
    return IReclaimQueue.SyncResult({
      logIndex: logIndex,
      reqIdFrom: reqIdFrom.toUint32(),
      reqIdTo: reqIdTo.toUint32(),
      totalSupply: totalSupply,
      totalAssets: totalAssets,
      totalSharesSynced: totalSharesSynced,
      totalAssetsOnReserve: totalAssetsOnReserve,
      totalAssetsOnRequest: totalAssetsOnRequest
    });
  }

  function makeClaimResult(uint256 reqIdFrom, uint256 reqIdTo, uint256 totalSharesClaimed, uint256 totalAssetsClaimed)
    internal
    pure
    returns (IReclaimQueue.ClaimResult memory)
  {
    return IReclaimQueue.ClaimResult({
      reqIdFrom: reqIdFrom.toUint32(),
      reqIdTo: reqIdTo.toUint32(),
      totalSharesClaimed: totalSharesClaimed,
      totalAssetsClaimed: totalAssetsClaimed
    });
  }

  function makeQueueInfo(bool isEnabled, uint256 reclaimPeriod, uint256 offset, uint256 itemsLen, uint256 syncLogsLen)
    internal
    pure
    returns (IReclaimQueue.QueueInfo memory)
  {
    return IReclaimQueue.QueueInfo({
      isEnabled: isEnabled,
      reclaimPeriod: reclaimPeriod.toUint48(),
      offset: offset.toUint32(),
      itemsLen: itemsLen.toUint32(),
      syncLogsLen: syncLogsLen.toUint32()
    });
  }

  function makeQueueIndexInfo(uint256 offset, uint256 size)
    internal
    pure //
    returns (IReclaimQueue.QueueIndexInfo memory)
  {
    return IReclaimQueue.QueueIndexInfo({
      offset: offset.toUint32(), //
      size: size.toUint32()
    });
  }

  // ================================================= ERRORS ================================================= //

  function _errQueueNotEnabled(address vault_) internal pure returns (bytes memory) {
    bytes4 selector = IReclaimQueue.IReclaimQueue__QueueNotEnabled.selector;
    return abi.encodeWithSelector(selector, vault_);
  }

  function _errNothingToClaim() internal pure returns (bytes memory) {
    bytes4 selector = IReclaimQueue.IReclaimQueue__NothingToClaim.selector;
    return abi.encodeWithSelector(selector);
  }

  function _errNothingToSync() internal pure returns (bytes memory) {
    bytes4 selector = IReclaimQueue.IReclaimQueue__NothingToSync.selector;
    return abi.encodeWithSelector(selector);
  }

  function _errEmpty() internal pure returns (bytes memory) {
    bytes4 selector = IReclaimQueue.IReclaimQueue__Empty.selector;
    return abi.encodeWithSelector(selector);
  }

  function _errOutOfBounds(uint256 max, uint256 actual) internal pure returns (bytes memory) {
    bytes4 selector = IReclaimQueue.IReclaimQueue__OutOfBounds.selector;
    return abi.encodeWithSelector(selector, max, actual);
  }

  // ================================================= COMPARE ================================================= //

  function _compareRequest(IReclaimQueue.Request memory expected, IReclaimQueue.Request memory actual) internal pure {
    assertEq(expected.timestamp, actual.timestamp, 'request.timestamp');
    assertEq(expected.assets, actual.assets, 'request.assets');
    assertEq(expected.sharesAcc, actual.sharesAcc, 'request.sharesAcc');
  }

  function _compareSyncLog(IReclaimQueue.SyncLog memory expected, IReclaimQueue.SyncLog memory actual) internal pure {
    assertEq(expected.timestamp, actual.timestamp, 'syncLog.timestamp');
    assertEq(expected.reqIdFrom, actual.reqIdFrom, 'syncLog.reqIdFrom');
    assertEq(expected.reqIdTo, actual.reqIdTo, 'syncLog.reqIdTo');
    assertEq(expected.sharesAcc, actual.sharesAcc, 'syncLog.sharesAcc');
    assertEq(expected.totalSupply, actual.totalSupply, 'syncLog.totalSupply');
    assertEq(expected.totalAssets, actual.totalAssets, 'syncLog.totalAssets');
  }

  function _compareSyncResult(IReclaimQueue.SyncResult memory expected, IReclaimQueue.SyncResult memory actual)
    internal
    pure
  {
    assertEq(expected.reqIdFrom, actual.reqIdFrom, 'syncResult.reqIdFrom');
    assertEq(expected.reqIdTo, actual.reqIdTo, 'syncResult.reqIdTo');
    assertEq(expected.totalSupply, actual.totalSupply, 'syncResult.totalSupply');
    assertEq(expected.totalAssets, actual.totalAssets, 'syncResult.totalAssets');
    assertEq(expected.totalSharesSynced, actual.totalSharesSynced, 'syncResult.totalSharesSynced');
    assertEq(expected.totalAssetsOnReserve, actual.totalAssetsOnReserve, 'syncResult.totalAssetsOnReserve');
    assertEq(expected.totalAssetsOnRequest, actual.totalAssetsOnRequest, 'syncResult.totalAssetsOnRequest');
  }

  function _compareQueueInfo(IReclaimQueue.QueueInfo memory expected, IReclaimQueue.QueueInfo memory actual)
    internal
    pure
  {
    assertEq(expected.isEnabled, actual.isEnabled, 'queueInfo.isEnabled');
    assertEq(expected.reclaimPeriod, actual.reclaimPeriod, 'queueInfo.reclaimPeriod');
    assertEq(expected.offset, actual.offset, 'queueInfo.offset');
    assertEq(expected.itemsLen, actual.itemsLen, 'queueInfo.itemsLen');
    assertEq(expected.syncLogsLen, actual.syncLogsLen, 'queueInfo.syncLogsLen');
  }

  function _compareQueueIndexInfo(
    IReclaimQueue.QueueIndexInfo memory expected,
    IReclaimQueue.QueueIndexInfo memory actual
  ) internal pure {
    assertEq(expected.offset, actual.offset, 'queueIndexInfo.offset');
    assertEq(expected.size, actual.size, 'queueIndexInfo.size');
  }
}

contract ReclaimQueueTest is ReclaimQueueTestHelper, Toolkit {
  using LibMockERC20 for address;
  using LibMockERC4626 for address;

  address owner = makeAddr('owner');
  address user = makeAddr('user');

  address assetManager;
  address asset;
  address vault;
  address asset2;
  address vault2;
  ReclaimQueue queue;

  function setUp() public {
    // set time to unix
    vm.warp(vm.unixTime() / 1000);

    assetManager = address(new MockContract());

    // setup asset and vault pair # 1
    {
      asset = address(new MockContract());
      asset.initMockERC20();
      asset.setRetERC20Decimals(18);
      vault = address(new SimpleERC4626Vault(asset, 'vault', 'vault'));
    }

    // setup asset and vault pair # 2
    {
      asset2 = address(new MockContract());
      asset2.initMockERC20();
      asset2.setRetERC20Decimals(18);
      vault2 = address(new SimpleERC4626Vault(asset2, 'vault2', 'vault2'));
    }

    // deploy reclaim queue
    {
      address impl = address(new ReclaimQueue());
      bytes memory initData = abi.encodeCall(ReclaimQueue.initialize, (owner, address(assetManager)));
      queue = ReclaimQueue(payable(_proxy(impl, initData)));
    }

    // enable vault1 by default
    {
      vm.startPrank(owner);
      queue.enableQueue(vault);
      queue.setReclaimPeriod(vault, 1 days);
      vm.stopPrank();
    }
  }

  function test_init() public view {
    assertEq(queue.assetManager(), assetManager, 'assetManager');
    assertTrue(queue.isEnabled(vault), 'vault1 enabled');
    assertFalse(queue.isEnabled(vault2), 'vault2 disabled');

    _compareQueueInfo(queue.queueInfo(vault), makeQueueInfo(true, 1 days, 0, 0, 0));
    _compareQueueInfo(queue.queueInfo(vault2), makeQueueInfo(false, 0, 0, 0, 0));
    _compareQueueIndexInfo(queue.queueIndex(vault, user), makeQueueIndexInfo(0, 0));
    _compareQueueIndexInfo(queue.queueIndex(vault2, user), makeQueueIndexInfo(0, 0));
  }

  function test_request(uint256 amount) public {
    vm.assume(0 < amount && amount <= 100 ether);

    vm.prank(user);
    SimpleERC4626Vault(vault).approve(address(queue), amount);
    SimpleERC4626Vault(vault).mint(user, amount);
    asset.setRetERC20BalanceOf(vault, amount);

    IReclaimQueue.Request memory expected = _request(amount, amount, 0);

    _compareQueueInfo(queue.queueInfo(vault), makeQueueInfo(true, 1 days, 0, 1, 0));
    _compareQueueIndexInfo(queue.queueIndex(vault, user), makeQueueIndexInfo(0, 1));
    _compareRequest(queue.queueItem(vault, 0), expected);
    _compareRequest(queue.queueIndexItem(vault, user, 0), expected);
  }

  function test_request_queueNotEnabled() public {
    vm.prank(user);
    vm.expectRevert(_errQueueNotEnabled(vault2));
    queue.request(100 ether, user, vault2);
  }

  function test_sync() public {
    // setup
    {
      vm.prank(user);
      SimpleERC4626Vault(vault).approve(address(queue), 300 ether);
      SimpleERC4626Vault(vault).mint(user, 300 ether);
      asset.setRetERC20BalanceOf(vault, 300 ether);

      _request(100 ether, 100 ether, 0);
      _request(100 ether, 100 ether, 1);
      _request(100 ether, 100 ether, 2);
    }

    // # 1
    {
      asset.setRetERC20BalanceOf(vault, 300 ether);
      uint256 expectedShares = 200 ether;
      uint256 expectedAssets = 200 ether;

      asset.setRetERC20Transfer(address(queue), expectedAssets);

      // check preview result
      {
        (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.previewSync(vault, 2);
        assertEq(totalSharesSynced, expectedShares, 'totalSharesSynced');
        assertEq(totalAssetsSynced, expectedAssets, 'totalAssetsSynced');
      }

      // check actual result
      {
        IReclaimQueue.SyncResult memory syncResult =
          makeSyncResult(0, 0, 2, 300 ether, 300 ether, expectedShares, expectedAssets, expectedShares);

        vm.prank(assetManager);
        vm.expectEmit();
        emit IReclaimQueue.Synced(owner, vault, syncResult);

        (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.sync(owner, vault, 2);
        assertEq(totalSharesSynced, expectedShares, 'totalSharesSynced');
        assertEq(totalAssetsSynced, expectedAssets, 'totalAssetsSynced');
      }

      asset.assertERC20Transfer(address(queue), expectedAssets);
      _compareSyncLog(queue.queueSyncLog(vault, 0), makeSyncLog(_now(), 0, 2, 200 ether, 300 ether, 300 ether));
    }

    // # 2
    {
      asset.setRetERC20BalanceOf(vault, 100 ether);
      uint256 expectedShares = 100 ether;
      uint256 expectedAssets = 100 ether;

      asset.setRetERC20Transfer(address(queue), expectedAssets);

      // check preview result
      {
        (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.previewSync(vault, 2);
        assertEq(totalSharesSynced, expectedShares, 'totalSharesSynced');
        assertEq(totalAssetsSynced, expectedAssets, 'totalAssetsSynced');
      }

      // check actual result
      {
        IReclaimQueue.SyncResult memory syncResult =
          makeSyncResult(1, 2, 3, 100 ether, 100 ether, expectedShares, expectedAssets, expectedShares);

        vm.prank(assetManager);
        vm.expectEmit();
        emit IReclaimQueue.Synced(owner, vault, syncResult);

        (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.sync(owner, vault, 2);
        assertEq(totalSharesSynced, expectedShares, 'totalSharesSynced');
        assertEq(totalAssetsSynced, expectedAssets, 'totalAssetsSynced');
      }

      asset.assertERC20Transfer(address(queue), expectedAssets);
      _compareSyncLog(queue.queueSyncLog(vault, 1), makeSyncLog(_now(), 2, 3, 300 ether, 100 ether, 100 ether));
    }

    _compareQueueInfo(queue.queueInfo(vault), makeQueueInfo(true, 1 days, 3, 3, 2));
  }

  function test_sync_loss() public {
    // setup
    {
      vm.prank(user);
      SimpleERC4626Vault(vault).approve(address(queue), 300 ether);
      SimpleERC4626Vault(vault).mint(user, 300 ether);
      asset.setRetERC20BalanceOf(vault, 300 ether);

      _request(100 ether, 100 ether, 0);
      _request(100 ether, 100 ether, 1);
      _request(100 ether, 100 ether, 2);
    }

    uint256 totalSupply = 300 ether;
    uint256 totalAssets = 150 ether; // 50% loss

    uint256 expectedSharesSynced = 300 ether;
    uint256 expectedAssetsOnRequest = 300 ether;
    uint256 expectedAssetsOnReserve = 150 ether;

    asset.setRetERC20BalanceOf(vault, totalAssets);
    asset.setRetERC20Transfer(address(queue), expectedAssetsOnRequest);

    // check preview result
    {
      (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.previewSync(vault, 100);
      assertEq(totalSharesSynced, expectedSharesSynced, 'totalSharesSynced');
      assertEq(totalAssetsSynced, expectedAssetsOnReserve, 'totalAssetsSynced');
    }

    // check actual result
    {
      IReclaimQueue.SyncResult memory syncResult = makeSyncResult(
        0, 0, 3, totalSupply, totalAssets, expectedSharesSynced, expectedAssetsOnReserve, expectedAssetsOnRequest
      );

      vm.prank(assetManager);
      vm.expectEmit();
      emit IReclaimQueue.Synced(owner, vault, syncResult);
      (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.sync(owner, vault, 100);
      assertEq(totalSharesSynced, expectedSharesSynced, 'totalSharesSynced');
      assertEq(totalAssetsSynced, expectedAssetsOnReserve, 'totalAssetsSynced');
    }

    asset.assertERC20Transfer(address(queue), expectedAssetsOnReserve);
    _compareSyncLog(queue.queueSyncLog(vault, 0), makeSyncLog(_now(), 0, 3, 300 ether, totalSupply, totalAssets));
  }

  function test_sync_yield() public {
    // setup
    {
      vm.prank(user);
      SimpleERC4626Vault(vault).approve(address(queue), 300 ether);
      SimpleERC4626Vault(vault).mint(user, 300 ether);
      asset.setRetERC20BalanceOf(vault, 300 ether);

      _request(100 ether, 100 ether, 0);
      _request(100 ether, 100 ether, 1);
      _request(100 ether, 100 ether, 2);
    }

    uint256 totalSupply = 300 ether;
    uint256 totalAssets = 450 ether; // 50% yield

    uint256 expectedSharesRemain = 100 ether - 1;
    uint256 expectedSharesSynced = 300 ether;
    uint256 expectedAssetsOnRequest = 300 ether;
    uint256 expectedAssetsOnReserve = 450 ether - 3;

    asset.setRetERC20BalanceOf(vault, totalAssets);
    asset.setRetERC20Transfer(address(queue), expectedAssetsOnRequest);

    // check preview result
    {
      (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.previewSync(vault, 100);
      assertEq(totalSharesSynced, expectedSharesSynced, 'totalSharesSynced');
      assertEq(totalAssetsSynced, expectedAssetsOnRequest, 'totalAssetsSynced');
    }

    // check actual result
    {
      IReclaimQueue.SyncResult memory syncResult = makeSyncResult(
        0, 0, 3, totalSupply, totalAssets, expectedSharesSynced, expectedAssetsOnReserve, expectedAssetsOnRequest
      );

      vm.prank(assetManager);
      vm.expectEmit();
      emit IReclaimQueue.Synced(owner, vault, syncResult);
      (uint256 totalSharesSynced, uint256 totalAssetsSynced) = queue.sync(owner, vault, 100);
      assertEq(totalSharesSynced, expectedSharesSynced, 'totalSharesSynced');
      assertEq(totalAssetsSynced, expectedAssetsOnRequest, 'totalAssetsSynced');
    }

    assertEq(SimpleERC4626Vault(vault).balanceOf(address(queue)), expectedSharesRemain, 'shares remain');
    asset.assertERC20Transfer(address(queue), expectedAssetsOnRequest);
    _compareSyncLog(queue.queueSyncLog(vault, 0), makeSyncLog(_now(), 0, 3, 300 ether, totalSupply, totalAssets));
  }

  function test_sync_unauthorized() public {
    vm.prank(user);
    vm.expectRevert(_errUnauthorized());
    queue.sync(user, vault, 100);
  }

  function test_sync_queueNotEnabled() public {
    vm.prank(assetManager);
    vm.expectRevert(_errQueueNotEnabled(vault2));
    queue.sync(assetManager, vault2, 100);
  }

  function test_sync_nothingToSync_init() public {
    vm.prank(assetManager);
    vm.expectRevert(_errNothingToSync());
    queue.sync(owner, vault, 100);
  }

  function test_sync_nothingToSync_afterRequest() public {
    test_sync();

    vm.prank(assetManager);
    vm.expectRevert(_errNothingToSync());
    queue.sync(owner, vault, 100);
  }

  function test_claim() public {
    // setup
    {
      vm.prank(user);
      SimpleERC4626Vault(vault).approve(address(queue), 600 ether);
      SimpleERC4626Vault(vault).mint(user, 600 ether);
      asset.setRetERC20BalanceOf(vault, 600 ether);

      _request(100 ether, 100 ether, 0);
      _request(100 ether, 100 ether, 1);
      _request(100 ether, 100 ether, 2);
      _request(100 ether, 100 ether, 3);
      _request(100 ether, 100 ether, 4);
      _request(100 ether, 100 ether, 5);
    }

    // # 1 sync
    asset.setRetERC20BalanceOf(vault, 300 ether);
    vm.prank(assetManager);
    queue.sync(owner, vault, 1);

    // # 2 sync: loss
    asset.setRetERC20BalanceOf(vault, 150 ether);
    vm.prank(assetManager);
    queue.sync(owner, vault, 1);

    // # 3 sync: yield
    asset.setRetERC20BalanceOf(vault, 450 ether);
    vm.prank(assetManager);
    queue.sync(owner, vault, 1);

    // pass reclaim period
    vm.warp(block.timestamp + 1 days);

    //======= TEST

    _compareQueueIndexInfo(queue.queueIndex(vault, user), makeQueueIndexInfo(0, 6));

    uint256 expectedClaimedShares = 300 ether;
    uint256 expectedClaimedAssets = 180 ether - 2;

    // check preview result
    {
      (uint256 totalSharesClaimed, uint256 totalAssetsClaimed) = queue.previewClaim(user, vault);
      assertEq(totalSharesClaimed, expectedClaimedShares, 'totalSharesClaimed');
      assertEq(totalAssetsClaimed, expectedClaimedAssets, 'totalAssetsClaimed');
    }

    // check actual result
    {
      vm.prank(user);

      vm.expectEmit();
      emit IReclaimQueue.Claimed(user, vault, 0, 100 ether, 50 ether - 1, 600 ether, 300 ether, 0);
      vm.expectEmit();
      emit IReclaimQueue.Claimed(user, vault, 1, 100 ether, 30 ether - 1, 500 ether, 150 ether, 1);
      vm.expectEmit();
      emit IReclaimQueue.Claimed(user, vault, 2, 100 ether, 100 ether, 400 ether, 450 ether, 2);
      vm.expectEmit();
      emit IReclaimQueue.ClaimSucceeded(user, vault, makeClaimResult(0, 3, 300 ether, 180 ether - 2));

      (uint256 totalSharesClaimed, uint256 totalAssetsClaimed) = queue.claim(user, vault);
      assertEq(totalSharesClaimed, expectedClaimedShares, 'totalSharesClaimed');
      assertEq(totalAssetsClaimed, expectedClaimedAssets, 'totalAssetsClaimed');
    }

    asset.assertERC20Transfer(user, expectedClaimedAssets);

    _compareQueueIndexInfo(queue.queueIndex(vault, user), makeQueueIndexInfo(3, 6));
  }

  function test_claim_queueNotEnabled() public {
    vm.prank(user);
    vm.expectRevert(_errQueueNotEnabled(vault2));
    queue.claim(user, vault2);
  }

  function test_claim_nothingToClaim_init() public {
    vm.prank(user);
    vm.expectRevert(_errNothingToClaim());
    queue.claim(user, vault);
  }

  function test_claim_nothingToClaim_afterRequest() public {
    test_claim();

    vm.prank(user);
    vm.expectRevert(_errNothingToClaim());
    queue.claim(user, vault);
  }

  function test_queueItem_validation() public {
    vm.expectRevert(_errEmpty());
    queue.queueItem(vault, 0);

    test_claim();

    vm.expectRevert(_errOutOfBounds(5, 6));
    queue.queueItem(vault, 6);
  }

  function test_queueIndexItem_validation() public {
    vm.expectRevert(_errEmpty());
    queue.queueIndexItem(vault, user, 0);

    test_claim();

    vm.expectRevert(_errOutOfBounds(5, 6));
    queue.queueIndexItem(vault, user, 6);
  }

  function test_queueSyncLog_validation() public {
    vm.expectRevert(_errEmpty());
    queue.queueSyncLog(vault, 0);

    test_claim();

    vm.expectRevert(_errOutOfBounds(2, 3));
    queue.queueSyncLog(vault, 3);
  }

  function _request(uint256 shares, uint256 assets, uint256 expectedReqId)
    internal
    returns (IReclaimQueue.Request memory)
  {
    vm.prank(user);
    vm.expectEmit();
    emit IReclaimQueue.Requested(user, vault, expectedReqId, shares, assets);
    uint256 reqId = queue.request(shares, user, vault);
    assertEq(reqId, expectedReqId, 'reqId');

    return makeRequest(_now48(), assets, shares);
  }
}
