// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IReclaimQueue {
  struct Request {
    uint48 timestamp;
    uint208 assets;
    uint208 sharesAcc;
  }

  struct SyncLog {
    uint48 timestamp;
    uint32 reqIdFrom;
    uint32 reqIdTo;
    uint144 sharesAcc;
    uint128 totalSupply;
    uint128 totalAssets;
  }

  struct SyncResult {
    uint256 logIndex;
    uint32 reqIdFrom;
    uint32 reqIdTo;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 totalSharesSynced;
    uint256 totalAssetsOnReserve;
    uint256 totalAssetsOnRequest;
  }

  struct ClaimResult {
    uint32 reqIdFrom;
    uint32 reqIdTo;
    uint256 totalSharesClaimed;
    uint256 totalAssetsClaimed;
  }

  struct QueueInfo {
    bool isEnabled;
    uint48 reclaimPeriod;
    uint32 offset;
    uint32 itemsLen;
    uint32 syncLogsLen;
  }

  struct QueueIndexInfo {
    uint32 offset;
    uint32 size;
  }

  event QueueEnabled(address indexed vault);
  event AssetManagerSet(address indexed assetManager);
  event ReclaimPeriodSet(address indexed vault, uint256 reclaimPeriod);
  event Requested(address indexed receiver, address indexed vault, uint256 reqId, uint256 shares, uint256 assets);
  event Claimed(
    address indexed receiver,
    address indexed vault,
    uint256 reqId,
    uint256 shares,
    uint256 assets,
    uint256 totalSupply,
    uint256 totalAssets,
    uint256 syncLogIndex
  );
  event ClaimSucceeded(address indexed receiver, address indexed vault, ClaimResult result);
  event Synced(address indexed executor, address indexed vault, SyncResult result);

  error IReclaimQueue__QueueNotEnabled(address vault);
  error IReclaimQueue__NothingToClaim();
  error IReclaimQueue__NothingToSync();
  error IReclaimQueue__Empty();
  error IReclaimQueue__OutOfBounds(uint256 max, uint256 actual);

  function assetManager() external view returns (address);
  function reclaimPeriod(address vault) external view returns (uint256);
  function isEnabled(address vault) external view returns (bool);

  function queueInfo(address vault) external view returns (QueueInfo memory);
  function queueItem(address vault, uint256 index) external view returns (Request memory);
  function queueIndex(address vault, address recipient) external view returns (QueueIndexInfo memory);
  function queueIndexItem(address vault, address recipient, uint32 index) external view returns (Request memory);
  function queueSyncLog(address vault, uint256 index) external view returns (SyncLog memory);

  function previewClaim(address receiver, address vault) external view returns (uint256, uint256);
  function previewSync(address vault, uint256 requestCount) external view returns (uint256, uint256);

  function request(uint256 shares, address receiver, address vault) external returns (uint256);
  function claim(address receiver, address vault) external returns (uint256, uint256);
  function sync(address executor, address vault, uint256 requestCount) external returns (uint256, uint256);

  function enableQueue(address vault) external;
  function setAssetManager(address assetManager_) external;
  function setReclaimPeriod(address vault, uint256 reclaimPeriod_) external;
}
