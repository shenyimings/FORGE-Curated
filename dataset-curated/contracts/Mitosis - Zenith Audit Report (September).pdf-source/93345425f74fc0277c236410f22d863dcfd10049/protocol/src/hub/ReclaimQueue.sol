// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { IERC4626 } from '@oz/interfaces/IERC4626.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';
import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IReclaimQueue } from '../interfaces/hub/IReclaimQueue.sol';
import { IReclaimQueueCollector } from '../interfaces/hub/IReclaimQueueCollector.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { LibQueue } from '../lib/LibQueue.sol';
import { Pausable } from '../lib/Pausable.sol';
import { StdError } from '../lib/StdError.sol';
import { Versioned } from '../lib/Versioned.sol';

contract ReclaimQueue is IReclaimQueue, Pausable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuard, Versioned {
  using SafeERC20 for IERC4626;
  using SafeERC20 for IERC20Metadata;
  using SafeCast for uint256;
  using ERC7201Utils for string;
  using Math for uint256;
  using LibQueue for LibQueue.UintOffsetQueue;

  struct QueueState {
    // configs
    bool isEnabled;
    uint48 reclaimPeriod;
    uint168 _reserved; // reserved for future usage
    // main
    uint32 offset;
    SyncLog[] logs;
    Request[] items;
    mapping(address recipient => LibQueue.UintOffsetQueue) indexes;
  }

  struct VaultState {
    // vault
    uint8 decimalsOffset;
    uint8 underlyingDecimals;
    // reserved for future usage
    uint240 _reserved;
  }

  struct StorageV1 {
    address resolver;
    address collector;
    mapping(address vault => QueueState) queues;
    mapping(address vault => VaultState) vaults;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ReclaimQueue.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  // =========================== NOTE: CONSTANTS =========================== //

  uint32 public constant MAX_CLAIM_SIZE = 100;

  // =========================== NOTE: INITIALIZATION =========================== //

  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, address resolver_, address collector_) public virtual initializer {
    __Pausable_init();
    __Ownable2Step_init();
    __Ownable_init(owner_);
    __UUPSUpgradeable_init();

    StorageV1 storage $ = _getStorageV1();

    _setResolver($, resolver_);
    _setCollector($, collector_);
  }

  // =========================== NOTE: QUERY FUNCTIONS =========================== //

  function resolver() external view returns (address) {
    return address(_getStorageV1().resolver);
  }

  function collector() external view returns (address) {
    return address(_getStorageV1().collector);
  }

  function reclaimPeriod(address vault) external view returns (uint256) {
    return _getStorageV1().queues[vault].reclaimPeriod;
  }

  function isEnabled(address vault) external view returns (bool) {
    return _getStorageV1().queues[vault].isEnabled;
  }

  function queueInfo(address vault) external view returns (QueueInfo memory) {
    QueueState storage q$ = _getStorageV1().queues[vault];

    return QueueInfo({
      isEnabled: q$.isEnabled,
      reclaimPeriod: q$.reclaimPeriod,
      offset: q$.offset,
      itemsLen: q$.items.length.toUint32(),
      syncLogsLen: q$.logs.length.toUint32()
    });
  }

  function queueItem(address vault, uint256 index) external view returns (Request memory) {
    QueueState storage q$ = _getStorageV1().queues[vault];
    _validateIndex(index, q$.items.length);
    return q$.items[index];
  }

  function queueIndex(address vault, address recipient) external view returns (QueueIndexInfo memory) {
    QueueState storage q$ = _getStorageV1().queues[vault];
    LibQueue.UintOffsetQueue storage i$ = q$.indexes[recipient];
    return QueueIndexInfo({ offset: i$.offset(), size: i$.size() });
  }

  function queueIndexItem(address vault, address recipient, uint32 index) external view returns (Request memory) {
    QueueState storage q$ = _getStorageV1().queues[vault];
    LibQueue.UintOffsetQueue storage i$ = q$.indexes[recipient];
    _validateIndex(index, i$.size());
    return q$.items[i$.itemAt(index)];
  }

  function queueSyncLog(address vault, uint256 index) external view returns (SyncLog memory) {
    QueueState storage q$ = _getStorageV1().queues[vault];
    _validateIndex(index, q$.logs.length);
    return q$.logs[index];
  }

  function pendingRequests(address vault, address recipient, uint256 offset, uint256 limit)
    external
    view
    returns (Request[] memory requests)
  {
    StorageV1 storage $ = _getStorageV1();
    QueueState storage q$ = $.queues[vault];
    LibQueue.UintOffsetQueue storage index = q$.indexes[recipient];

    uint32 reqIdFrom = index.offset() + offset.toUint32();
    uint32 reqIdTo = Math.min(reqIdFrom + limit.toUint32(), index.size()).toUint32();
    if (reqIdFrom >= reqIdTo) return new Request[](0);

    requests = new Request[](reqIdTo - reqIdFrom);
    for (uint32 i = reqIdFrom; i < reqIdTo; i++) {
      requests[i - reqIdFrom] = q$.items[index.itemAt(i)];
    }
  }

  function previewClaim(address receiver, address vault) external view returns (ClaimResult memory) {
    return _previewClaimPagination(_getStorageV1(), receiver, vault, 0, MAX_CLAIM_SIZE);
  }

  function previewClaimPagination(address receiver, address vault, uint256 offset, uint256 limit)
    external
    view
    returns (ClaimResult memory)
  {
    return _previewClaimPagination(_getStorageV1(), receiver, vault, offset, limit);
  }

  function previewSync(address vault, uint256 requestCount) external view returns (uint256, uint256) {
    StorageV1 storage $ = _getStorageV1();
    SyncResult memory res = _calcSync($.queues[vault], vault, requestCount);
    return (res.totalSharesSynced, Math.min(res.totalAssetsOnRequest, res.totalAssetsOnReserve));
  }

  function previewSyncWithBudget(address vault, uint256 budget)
    external
    view
    returns (uint256 totalSharesSynced, uint256 totalAssetsSynced, uint256 totalSyncedRequestsCount)
  {
    StorageV1 storage $ = _getStorageV1();
    QueueState storage q$ = $.queues[vault];

    uint32 reqIdFrom = q$.offset;
    uint32 reqIdTo = q$.items.length.toUint32();

    for (uint32 i = reqIdFrom; i < reqIdTo;) {
      Request memory req = q$.items[i];

      uint256 shares = i == 0 ? req.sharesAcc : req.sharesAcc - q$.items[i - 1].sharesAcc;
      uint256 assets = Math.min(req.assets, IERC4626(vault).previewRedeem(shares));

      if (budget < assets) break;
      budget -= assets;

      totalSharesSynced += shares;
      totalAssetsSynced += assets;
      totalSyncedRequestsCount++;

      unchecked {
        ++i;
      } // Use unchecked for gas savings
    }
  }

  // =========================== NOTE: QUEUE FUNCTIONS =========================== //

  function request(uint256 shares, address receiver, address vault) public whenNotPaused returns (uint256) {
    QueueState storage q$ = _getStorageV1().queues[vault];

    require(q$.isEnabled, IReclaimQueue__QueueNotEnabled(vault));

    IERC4626(vault).safeTransferFrom(_msgSender(), address(this), shares);

    uint256 assets = IERC4626(vault).previewRedeem(shares);

    uint48 now_ = Time.timestamp();

    uint256 reqId = q$.items.length;

    {
      uint208 assets208 = assets.toUint208();
      uint208 shares208 = shares.toUint208();

      if (reqId == 0) q$.items.push(Request(now_, assets208, shares208));
      else q$.items.push(Request(now_, assets208, q$.items[reqId - 1].sharesAcc + shares208));
    }

    q$.indexes[receiver].append(reqId);

    emit Requested(receiver, vault, reqId, shares, assets);

    return reqId;
  }

  function claim(address receiver, address vault) external nonReentrant whenNotPaused returns (ClaimResult memory) {
    StorageV1 storage $ = _getStorageV1();
    {
      QueueState storage q$ = $.queues[vault];
      LibQueue.UintOffsetQueue storage index = q$.indexes[receiver];

      uint32 indexSize = index.size();

      require(q$.isEnabled, IReclaimQueue__QueueNotEnabled(vault));
      require(indexSize != 0, IReclaimQueue__NothingToClaim());
      require(index.offset() < indexSize, IReclaimQueue__NothingToClaim());
    }

    // run actual claim logic
    ClaimResult memory res = _claim($, receiver, vault);
    require(res.totalAssetsClaimed > 0, IReclaimQueue__NothingToClaim());

    emit ClaimSucceeded(receiver, vault, res);

    // send total claim amount to receiver
    IERC20Metadata(IERC4626(vault).asset()).safeTransfer(receiver, res.totalAssetsClaimed);

    return res;
  }

  function sync(address executor, address vault, uint256 requestCount)
    external
    whenNotPaused
    returns (uint256, uint256)
  {
    StorageV1 storage $ = _getStorageV1();

    require(_msgSender() == $.resolver, StdError.Unauthorized());
    require($.queues[vault].isEnabled, IReclaimQueue__QueueNotEnabled(vault));

    SyncResult memory res = _sync($, vault, requestCount);
    emit Synced(executor, vault, res);

    return (res.totalSharesSynced, Math.min(res.totalAssetsOnRequest, res.totalAssetsOnReserve));
  }

  // =========================== NOTE: OWNABLE FUNCTIONS =========================== //

  function _authorizeUpgrade(address) internal override onlyOwner { }

  function _authorizePause(address) internal view override onlyOwner { }

  function enableQueue(address vault) external onlyOwner {
    _enableQueue(_getStorageV1(), vault);
  }

  function disableQueue(address vault) external onlyOwner {
    _disableQueue(_getStorageV1(), vault);
  }

  function setResolver(address resolver_) external onlyOwner {
    _setResolver(_getStorageV1(), resolver_);
  }

  function setCollector(address collector_) external onlyOwner {
    _setCollector(_getStorageV1(), collector_);
  }

  function setReclaimPeriod(address vault, uint256 reclaimPeriod_) external onlyOwner {
    _setReclaimPeriod(_getStorageV1(), vault, reclaimPeriod_);
  }

  // =========================== NOTE: INTERNAL FUNCTIONS =========================== //

  function _convertToAssets(
    uint256 shares,
    uint8 decimalsOffset,
    uint256 totalAssets,
    uint256 totalSupply,
    Math.Rounding rounding
  ) private pure returns (uint256) {
    return shares.mulDiv(totalAssets, totalSupply + 10 ** decimalsOffset, rounding);
  }

  struct CalcClaimState {
    uint256 cachedLogPos;
    SyncLog cached;
    uint32 queueOffset;
    uint48 reqTimeBoundary;
  }

  function _fetchInitialCalcClaimState(QueueState storage q$) internal view returns (CalcClaimState memory state) {
    if (q$.logs.length == 0) {
      return state;
    }

    uint256 cachedLogPos = q$.logs.length - 1;
    SyncLog memory cached = _unsafeAccess(q$.logs, cachedLogPos);

    state = CalcClaimState({
      cachedLogPos: cachedLogPos,
      cached: cached,
      queueOffset: q$.offset,
      reqTimeBoundary: Time.timestamp() - q$.reclaimPeriod
    });
  }

  function _fetchSyncLogByReqId(QueueState storage q$, uint256 reqId) internal view returns (SyncLog memory, uint256) {
    SyncLog[] storage syncLogs = q$.logs;
    uint256 syncLogsLen = syncLogs.length;

    uint256 pos = _lowerBinaryLookup(syncLogs, reqId, 0, syncLogsLen);
    SyncLog memory log = _unsafeAccess(syncLogs, pos);

    return (log, pos);
  }

  function _previewClaimPagination(StorageV1 storage $, address receiver, address vault, uint256 offset, uint256 limit)
    internal
    view
    returns (ClaimResult memory res)
  {
    LibQueue.UintOffsetQueue storage index = $.queues[vault].indexes[receiver];

    uint32 reqIdFrom = index.offset() + offset.toUint32();
    uint32 reqIdTo = Math.min(reqIdFrom + limit.toUint32(), index.size()).toUint32();
    if (reqIdFrom >= reqIdTo) return res;

    res = _calcClaim(
      $.queues[vault],
      ClaimResult({
        reqIdFrom: reqIdFrom, //
        reqIdTo: reqIdTo,
        totalSharesClaimed: 0,
        totalAssetsClaimed: 0
      }),
      receiver,
      $.vaults[vault].decimalsOffset
    );
  }

  function _calcClaim(QueueState storage q$, ClaimResult memory res, address receiver, uint8 decimalsOffset)
    internal
    view
    returns (ClaimResult memory)
  {
    CalcClaimState memory state = _fetchInitialCalcClaimState(q$);
    LibQueue.UintOffsetQueue storage index = q$.indexes[receiver];

    for (uint32 i = res.reqIdFrom; i < res.reqIdTo;) {
      uint256 reqId = index.itemAt(i);
      Request memory req = q$.items[reqId];

      // if the request didn't pass the reclaim period or before the sync, stop the loop
      if (state.queueOffset <= reqId || state.reqTimeBoundary < req.timestamp) {
        res.reqIdTo = i;
        break;
      }

      if (reqId < state.cached.reqIdFrom || state.cached.reqIdTo <= reqId) {
        (state.cached, state.cachedLogPos) = _fetchSyncLogByReqId(q$, reqId);
      }

      uint256 shares = i == 0 ? req.sharesAcc : req.sharesAcc - q$.items[reqId - 1].sharesAcc;
      uint256 assets = Math.min(
        req.assets,
        _convertToAssets(
          shares, //
          decimalsOffset,
          state.cached.totalAssets,
          state.cached.totalSupply,
          Math.Rounding.Floor
        )
      );

      res.totalSharesClaimed += shares;
      res.totalAssetsClaimed += assets;

      unchecked {
        ++i;
      } // Use unchecked for gas savings
    }

    return res;
  }

  function _execClaim(
    QueueState storage q$,
    ClaimResult memory res,
    address vault,
    address receiver,
    uint8 decimalsOffset
  ) internal returns (ClaimResult memory) {
    CalcClaimState memory state = _fetchInitialCalcClaimState(q$);
    LibQueue.UintOffsetQueue storage index = q$.indexes[receiver];

    for (uint32 i = res.reqIdFrom; i < res.reqIdTo;) {
      uint256 reqId = index.itemAt(i);
      Request memory req = q$.items[reqId];

      // if the request didn't pass the reclaim period or before the sync, stop the loop
      if (state.queueOffset <= reqId || state.reqTimeBoundary < req.timestamp) {
        res.reqIdTo = i;
        break;
      }

      if (reqId < state.cached.reqIdFrom || state.cached.reqIdTo <= reqId) {
        (state.cached, state.cachedLogPos) = _fetchSyncLogByReqId(q$, reqId);
      }

      uint256 shares = i == 0 ? req.sharesAcc : req.sharesAcc - q$.items[reqId - 1].sharesAcc;
      uint256 assets = Math.min(
        req.assets,
        _convertToAssets(
          shares, //
          decimalsOffset,
          state.cached.totalAssets,
          state.cached.totalSupply,
          Math.Rounding.Floor
        )
      );

      emit Claimed(
        receiver, //
        vault,
        reqId,
        shares,
        assets,
        state.cached.totalSupply,
        state.cached.totalAssets,
        state.cachedLogPos
      );

      res.totalSharesClaimed += shares;
      res.totalAssetsClaimed += assets;

      unchecked {
        ++i;
      } // Use unchecked for gas savings
    }

    return res;
  }

  function _claim(StorageV1 storage $, address receiver, address vault) internal returns (ClaimResult memory) {
    QueueState storage q$ = $.queues[vault];
    LibQueue.UintOffsetQueue storage index = q$.indexes[receiver];

    uint32 reqIdFrom = index.offset();
    uint32 reqIdTo = Math.min(reqIdFrom + MAX_CLAIM_SIZE, index.size()).toUint32();

    ClaimResult memory res = _execClaim(
      q$,
      ClaimResult({
        reqIdFrom: reqIdFrom, //
        reqIdTo: reqIdTo,
        totalSharesClaimed: 0,
        totalAssetsClaimed: 0
      }),
      vault,
      receiver,
      $.vaults[vault].decimalsOffset
    );

    // update index offset if there's at least one request to be claimed
    if (res.reqIdFrom < res.reqIdTo) index._offset = res.reqIdTo;

    return res;
  }

  function _calcSync(QueueState storage q$, address vault, uint256 requestCount)
    internal
    view
    returns (SyncResult memory)
  {
    // reuse to avoid duplicate SLOAD
    uint256 itemsLen = q$.items.length;
    uint32 reqIdFrom = q$.offset;
    uint32 reqIdTo = Math.min(reqIdFrom + requestCount, itemsLen).toUint32();

    SyncResult memory res = SyncResult({
      logIndex: q$.logs.length,
      reqIdFrom: reqIdFrom,
      reqIdTo: reqIdTo,
      totalSupply: IERC4626(vault).totalSupply(),
      totalAssets: IERC4626(vault).totalAssets(),
      totalSharesSynced: 0,
      totalAssetsOnReserve: 0,
      totalAssetsOnRequest: 0
    });

    for (uint32 i = res.reqIdFrom; i < res.reqIdTo;) {
      Request memory req = q$.items[i];

      uint256 shares = i == 0 ? req.sharesAcc : req.sharesAcc - q$.items[i - 1].sharesAcc;

      res.totalSharesSynced += shares;
      res.totalAssetsOnRequest += req.assets;
      res.totalAssetsOnReserve += IERC4626(vault).previewRedeem(shares);

      unchecked {
        ++i;
      } // Use unchecked for gas savings
    }

    return res;
  }

  function _sync(StorageV1 storage $, address vault, uint256 requestCount) internal returns (SyncResult memory) {
    QueueState storage q$ = $.queues[vault];
    require(q$.items.length != 0, IReclaimQueue__NothingToSync());

    SyncResult memory res = _calcSync(q$, vault, requestCount);
    require(res.reqIdTo > q$.offset, IReclaimQueue__NothingToSync());

    uint256 withdrawAmount = Math.min(res.totalAssetsOnRequest, res.totalAssetsOnReserve);
    IERC4626(vault).withdraw(withdrawAmount, address(this), address(this));

    if (res.totalAssetsOnRequest < res.totalAssetsOnReserve) {
      uint256 assetsCollected = res.totalAssetsOnReserve - res.totalAssetsOnRequest;
      uint256 sharesCollected = IERC4626(vault).previewWithdraw(assetsCollected);

      IERC20Metadata(vault).forceApprove($.collector, sharesCollected);
      IReclaimQueueCollector($.collector).collect(vault, vault, sharesCollected);
      IERC20Metadata(vault).forceApprove($.collector, 0);
    }

    {
      SyncLog[] storage syncLogs = q$.logs;

      uint256 syncLogsLen = syncLogs.length;
      uint256 nextSharesAcc =
        syncLogsLen == 0 ? res.totalSharesSynced : syncLogs[syncLogsLen - 1].sharesAcc + res.totalSharesSynced;

      res.logIndex = syncLogs.length;

      syncLogs.push(
        SyncLog({
          timestamp: Time.timestamp(),
          reqIdFrom: res.reqIdFrom,
          reqIdTo: res.reqIdTo,
          sharesAcc: nextSharesAcc.toUint144(),
          totalSupply: res.totalSupply.toUint128(),
          totalAssets: res.totalAssets.toUint128()
        })
      );
    }

    q$.offset = res.reqIdTo;

    return res;
  }

  function _enableQueue(StorageV1 storage $, address vault) internal {
    $.queues[vault].isEnabled = true;

    uint8 underlyingDecimals = IERC20Metadata(IERC4626(vault).asset()).decimals();
    $.vaults[vault].underlyingDecimals = underlyingDecimals;
    $.vaults[vault].decimalsOffset = IERC4626(vault).decimals() - underlyingDecimals;

    emit QueueEnabled(vault);
  }

  function _disableQueue(StorageV1 storage $, address vault) internal {
    $.queues[vault].isEnabled = false;

    emit QueueDisabled(vault);
  }

  function _setResolver(StorageV1 storage $, address resolver_) internal {
    $.resolver = resolver_;
    emit ResolverSet(resolver_);
  }

  function _setCollector(StorageV1 storage $, address collector_) internal {
    $.collector = collector_;
    emit CollectorSet(collector_);
  }

  function _setReclaimPeriod(StorageV1 storage $, address vault, uint256 reclaimPeriod_) internal {
    require($.queues[vault].isEnabled, IReclaimQueue__QueueNotEnabled(vault));

    $.queues[vault].reclaimPeriod = reclaimPeriod_.toUint48();

    emit ReclaimPeriodSet(vault, reclaimPeriod_);
  }

  function _lowerBinaryLookup(SyncLog[] storage self, uint256 reqId, uint256 low, uint256 high)
    private
    view
    returns (uint256)
  {
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self, mid).reqIdTo <= reqId) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return high;
  }

  function _unsafeAccess(SyncLog[] storage self, uint256 pos) private pure returns (SyncLog storage result) {
    assembly {
      // Get the array's storage slot
      mstore(0, self.slot)
      // Multiply position by 2 (since each element takes 2 storage slots)
      let slotOffset := shl(1, pos)
      // Add the offset to the base storage location
      result.slot := add(keccak256(0, 0x20), slotOffset)
    }
  }

  function _validateIndex(uint256 index, uint256 length) private pure {
    require(length != 0, IReclaimQueue__Empty());
    require(length - 1 >= index, IReclaimQueue__OutOfBounds(length - 1, index));
  }
}
