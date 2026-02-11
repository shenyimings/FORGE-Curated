// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/**
 * @title IAssetManagerStorageV1
 * @notice Interface for the storage component of the AssetManager
 */
interface IAssetManagerStorageV1 {
  /**
   * @notice Emitted when a new entrypoint is set
   * @param entrypoint The address of the new entrypoint
   */
  event EntrypointSet(address indexed entrypoint);

  /**
   * @notice Emitted when a new reclaim queue is set
   * @param reclaimQueue_ The address of the new reclaim queue
   */
  event ReclaimQueueSet(address indexed reclaimQueue_);

  /**
   * @notice Emitted when a new reward treasury is set
   * @param treasury The address of the new treasury
   */
  event TreasurySet(address indexed treasury);

  /**
   * @notice Emitted when a new hub asset factory is set
   * @param hubAssetFactory The address of the new hub asset factory
   */
  event HubAssetFactorySet(address indexed hubAssetFactory);

  /**
   * @notice Emitted when a new VLFVaultFactory is set
   * @param vlfVaultFactory The address of the new VLFVaultFactory
   */
  event VLFVaultFactorySet(address indexed vlfVaultFactory);

  /**
   * @notice Emitted when a new strategist is set for a VLFVault
   * @param vlfVault The address of the VLFVault
   * @param strategist The address of the new strategist
   */
  event StrategistSet(address indexed vlfVault, address indexed strategist);

  /**
   * @notice Emitted when the withdrawable deposit threshold is updated for a hub asset on a specific chain
   * @param hubAsset The address of the hub asset for which the threshold is set
   * @param chainId The ID of the chain where the threshold is applied
   * @param threshold The new withdrawable deposit threshold amount
   */
  event BranchLiquidityThresholdSet(address indexed hubAsset, uint256 indexed chainId, uint256 threshold);

  //=========== NOTE: ERROR DEFINITIONS ===========//

  error IAssetManagerStorageV1__HubAssetPairNotExist(address hubAsset);

  error IAssetManagerStorageV1__BranchAssetPairNotExist(uint256 chainId, address branchAsset);
  error IAssetManagerStorageV1__TreasuryNotSet();

  error IAssetManagerStorageV1__HubAssetFactoryNotSet();
  error IAssetManagerStorageV1__InvalidHubAsset(address hubAsset);

  error IAssetManagerStorageV1__VLFVaultFactoryNotSet();
  error IAssetManagerStorageV1__InvalidVLFVault(address vlfVault);
  error IAssetManagerStorageV1__VLFNotInitialized(uint256 chainId, address vlfVault);
  error IAssetManagerStorageV1__VLFAlreadyInitialized(uint256 chainId, address vlfVault);

  error IAssetManagerStorageV1__BranchAvailableLiquidityInsufficient(
    uint256 chainId, address hubAsset, uint256 available, uint256 amount
  );

  error IAssetManagerStorageV1__BranchLiquidityThresholdNotSatisfied(
    uint256 chainId, address hubAsset, uint256 threshold, uint256 amount
  );

  //=========== NOTE: STATE GETTERS ===========//

  /**
   * @notice Get the current entrypoint address (see IAssetManagerEntrypoint)
   */
  function entrypoint() external view returns (address);

  /**
   * @notice Get the current reclaim queue address (see IReclaimQueue)
   */
  function reclaimQueue() external view returns (address);

  /**
   * @notice Get the current reward treasury address (see ITreasury)
   */
  function treasury() external view returns (address);

  /**
   * @notice Get the current hub asset factory address (see IHubAssetFactory)
   */
  function hubAssetFactory() external view returns (address);

  /**
   * @notice Get the current VLFVaultFactory address (see IVLFVaultFactory)
   */
  function vlfVaultFactory() external view returns (address);

  /**
   * @notice Get the branch asset address for a given hub asset and chain ID
   * @param hubAsset_ The address of the hub asset
   * @param chainId The ID of the chain
   */
  function branchAsset(address hubAsset_, uint256 chainId) external view returns (address);

  /**
   * @notice Get the total liquidity amount of branch asset for a given hub asset and chain ID
   * @dev The liquidity amount is equals to the total amount of branch asset deposited to the MitosisVault
   * @param hubAsset_ The address of the hub asset
   * @param chainId The ID of the chain
   */
  function branchLiquidity(address hubAsset_, uint256 chainId) external view returns (uint256);

  /**
   * @notice Get the allocated amount of a branch asset for a given hub asset and chain ID
   * @param hubAsset_ The address of the hub asset
   * @param chainId The ID of the chain
   */
  function branchAllocated(address hubAsset_, uint256 chainId) external view returns (uint256);

  /**
   * @notice Retrieves the withdrawable deposit threshold for a given hub asset and chain ID
   * @param hubAsset_ The address of the hub asset
   * @param chainId The ID of the chain
   */
  function branchLiquidityThreshold(address hubAsset_, uint256 chainId) external view returns (uint256);

  /**
   * @notice Retrieves the decimal places for a branch asset on a given chain
   * @param hubAsset_ The address of the hub asset
   * @param chainId The ID of the chain
   */
  function branchAssetDecimals(address hubAsset_, uint256 chainId) external view returns (uint8);

  /**
   * @notice Get the available liquidity of branch asset for a given hub asset and chain ID
   * @dev The available amount of branch asset can be used for withdrawal or allocation.
   * @param hubAsset_ The address of the hub asset
   * @param chainId The ID of the chain
   */
  function branchAvailableLiquidity(address hubAsset_, uint256 chainId) external view returns (uint256);

  /**
   * @notice Get the hub asset address for a given chain ID and branch asset
   * @param chainId The ID of the chain
   * @param branchAsset_ The address of the branch asset
   */
  function hubAsset(uint256 chainId, address branchAsset_) external view returns (address);

  /**
   * @notice Check if a VLF is initialized for a given chain and branch asset (VLFVault -> hubAsset -> branchAsset)
   * @param chainId The ID of the chain
   * @param vlfVault The address of the VLFVault
   */
  function vlfInitialized(uint256 chainId, address vlfVault) external view returns (bool);

  /**
   * @notice Get the idle balance of a VLF
   * @dev The idle balance will be calculated like this:
   * @dev (total supplied amount - total utilized amount - total pending reclaim amount)
   * @param vlfVault The address of the VLFVault
   */
  function vlfIdle(address vlfVault) external view returns (uint256);

  /**
   * @notice Get the total utilized balance (hubAsset/branchAsset) of a VLF
   * @param vlfVault The address of the VLFVault
   */
  function vlfAlloc(address vlfVault) external view returns (uint256);

  /**
   * @notice Get the strategist address for a VLF
   * @param vlfVault The address of the VLFVault
   */
  function strategist(address vlfVault) external view returns (address);
}

/**
 * @title IAssetManager
 * @notice Interface for the main Asset Manager contract
 */
interface IAssetManager is IAssetManagerStorageV1 {
  /**
   * @notice Emitted when an asset is initialized
   * @param hubAsset The address of the hub asset
   * @param chainId The ID of the chain where the asset is initialized
   * @param branchAsset The address of the initialized branch asset
   * @param branchAssetDecimals The decimals of the initialized branch asset
   */
  event AssetInitialized(
    address indexed hubAsset, uint256 indexed chainId, address branchAsset, uint8 branchAssetDecimals
  );

  /**
   * @notice Emitted when a VLF is initialized
   * @param hubAsset The address of the hub asset
   * @param chainId The ID of the chain where the VLF is initialized
   * @param vlfVault The address of the initialized VLFVault
   * @param branchAsset The address of the branch asset associated with the VLF
   */
  event VLFInitialized(address indexed hubAsset, uint256 indexed chainId, address vlfVault, address branchAsset);

  /**
   * @notice Emitted when a deposit is made
   * @param chainId The ID of the chain where the deposit is made
   * @param hubAsset The address of the asset that correspond to the branch asset
   * @param to The address receiving the hubAsset
   * @param amount The amount deposited
   */
  event Deposited(uint256 indexed chainId, address indexed hubAsset, address indexed to, uint256 amount);

  /**
   * @notice Emitted when a deposit is made with supply to a VLF
   * @param chainId The ID of the chain where the deposit is made
   * @param hubAsset The address of the asset that correspond to the branch asset
   * @param to The address receiving the miAsset
   * @param vlfVault The address of the VLFVault supplied into
   * @param amount The amount deposited
   * @param supplyAmount The amount supplied into the VLF
   */
  event DepositedWithSupplyVLF(
    uint256 indexed chainId,
    address indexed hubAsset,
    address indexed to,
    address vlfVault,
    uint256 amount,
    uint256 supplyAmount
  );

  /**
   * @notice Emitted when hubAssets are withdrawn
   * @param chainId The ID of the chain where the withdrawal occurs
   * @param hubAsset The address of the withdrawn asset
   * @param to The address receiving the withdrawn assets on the branch chain
   * @param amount The hubAsset amount to be withdrawn
   * @param amountBranchUnit The branch asset amount to be actual withdrawn
   */
  event Withdrawn(
    uint256 indexed chainId, address indexed hubAsset, address indexed to, uint256 amount, uint256 amountBranchUnit
  );

  /**
   * @notice Emitted when a reward is settled from the branch chain to the hub chain for a specific VLF
   * @param chainId The ID of the chain where the reward is reported
   * @param vlfVault The address of the VLFVault receiving the reward
   * @param asset The address of the reward asset
   * @param amount The amount of the reward
   */
  event VLFRewardSettled(uint256 indexed chainId, address indexed vlfVault, address indexed asset, uint256 amount);

  /**
   * @notice Emitted when a loss is settled from the branch chain to the hub chain for a specific VLF
   * @param chainId The ID of the chain where the loss is reported
   * @param vlfVault The address of the VLFVault incurring the loss
   * @param asset The address of the asset lost
   * @param amount The amount of the loss
   */
  event VLFLossSettled(uint256 indexed chainId, address indexed vlfVault, address indexed asset, uint256 amount);

  /**
   * @notice Emitted when assets are allocated to the branch chain for a specific VLF
   * @param strategist The address of the strategist
   * @param chainId The ID of the chain where the allocation occurs
   * @param vlfVault The address of the VLFVault to be reported the allocation
   * @param amount The amount allocated
   * @param amountBranchUnit The branch asset amount to be actual allocation
   */
  event VLFAllocated(
    address indexed strategist,
    uint256 indexed chainId,
    address indexed vlfVault,
    uint256 amount,
    uint256 amountBranchUnit
  );

  /**
   * @notice Emitted when assets are deallocated from the branch chain for a specific VLF
   * @param chainId The ID of the chain where the deallocation occurs
   * @param vlfVault The address of the VLFVault to be reported the deallocation
   * @param amount The amount deallocated
   */
  event VLFDeallocated(uint256 indexed chainId, address indexed vlfVault, uint256 amount);

  /**
   * @notice Emitted when a claim request is reserved from the reclaim queue
   * @param strategist The address of the strategist
   * @param vlfVault The address of the VLFVault to be reported the claim request
   * @param claimCount The amount of the claim request
   * @param totalReservedShares The total amount of shares reserved
   * @param totalReservedAssets The total amount of assets reserved
   */
  event VLFReserved(
    address indexed strategist,
    address indexed vlfVault,
    uint256 claimCount,
    uint256 totalReservedShares,
    uint256 totalReservedAssets
  );

  /**
   * @notice Emitted when an asset pair is set
   * @param hubAsset The address of the hub asset
   * @param branchChainId The ID of the branch chain
   * @param branchAsset The address of the branch asset
   * @param branchAssetDecimals The decimals of the branch asset
   */
  event AssetPairSet(address hubAsset, uint256 branchChainId, address branchAsset, uint8 branchAssetDecimals);

  /**
   * @notice Error thrown when a VLF has no claimable amount
   * @param vlfVault The address of the VLFVault with no claimable amount
   */
  error IAssetManager__NothingToVLFReserve(address vlfVault);

  /**
   * @notice Error thrown when a VLF has insufficient funds
   * @param vlfVault The address of the VLFVault with insufficient funds
   */
  error IAssetManager__VLFLiquidityInsufficient(address vlfVault);

  /**
   * @notice Check if an address is the owner of the contract
   * @param account The address to check
   * @return True if the address is the owner, false otherwise
   */
  function isOwner(address account) external view returns (bool);

  /**
   * @notice Check if an address is a liquidity manager
   * @param account The address to check
   * @return True if the address is a liquidity manager, false otherwise
   */
  function isLiquidityManager(address account) external view returns (bool);

  /**
   * @notice Quotes the gas fee for initializing an asset on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param branchAsset The address of the asset on the branch chain
   * @return The gas fee required for the operation
   */
  function quoteInitializeAsset(uint256 chainId, address branchAsset) external view returns (uint256);

  /**
   * @notice Quotes the gas fee for initializing a VLF on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param vlfVault The address of the VLFVault
   * @param branchAsset The address of the associated asset on the branch chain
   * @return The gas fee required for the operation
   */
  function quoteInitializeVLF(uint256 chainId, address vlfVault, address branchAsset) external view returns (uint256);

  /**
   * @notice Quotes the gas fee for withdrawing assets from a branch chain
   * @param chainId The ID of the branch chain
   * @param branchAsset The address of the asset on the branch chain
   * @param to The address that will receive the withdrawn assets
   * @param amount The amount of assets to withdraw
   * @return The gas fee required for the operation
   */
  function quoteWithdraw(uint256 chainId, address branchAsset, address to, uint256 amount)
    external
    view
    returns (uint256);

  /**
   * @notice Quotes the gas fee for allocating assets to a VLF on a specified branch chain
   * @param chainId The ID of the branch chain
   * @param vlfVault The address of the VLFVault
   * @param amount The amount of assets to allocate
   * @return The gas fee required for the operation
   */
  function quoteAllocateVLF(uint256 chainId, address vlfVault, uint256 amount) external view returns (uint256);

  /**
   * @notice Deposit branch assets
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the deposit is made
   * @param branchAsset The address of the branch asset being deposited
   * @param to The address receiving the deposit
   * @param amount The amount to deposit
   */
  function deposit(uint256 chainId, address branchAsset, address to, uint256 amount) external;

  /**
   * @notice Deposit branch assets with supply to a VLF
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the deposit is made
   * @param branchAsset The address of the branch asset being deposited
   * @param to The address receiving the deposit
   * @param vlfVault The address of the VLFVault to supply into
   * @param amount The amount to deposit
   */
  function depositWithSupplyVLF(uint256 chainId, address branchAsset, address to, address vlfVault, uint256 amount)
    external;

  /**
   * @notice Withdraw hub assets and receive the asset on the branch chain
   * @dev Dispatches the cross-chain message to branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the withdrawal occurs
   * @param hubAsset The address of the hub asset to withdraw
   * @param to The address receiving the withdrawn assets
   * @param amount The amount to withdraw
   */
  function withdraw(uint256 chainId, address hubAsset, address to, uint256 amount) external payable;

  /**
   * @notice Allocate the assets to the branch chain for a specific VLF
   * @dev Only the strategist of the VLF can allocate assets
   * @dev Dispatches the cross-chain message to branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the allocation occurs
   * @param vlfVault The address of the VLFVault to be affected
   * @param amount The amount to allocate
   */
  function allocateVLF(uint256 chainId, address vlfVault, uint256 amount) external payable;

  /**
   * @notice Deallocate the assets from the branch chain for a specific VLF
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the deallocation occurs
   * @param vlfVault The address of the VLFVault to be affected
   * @param amount The amount to deallocate
   */
  function deallocateVLF(uint256 chainId, address vlfVault, uint256 amount) external;

  /**
   * @notice Resolves the pending reclaim request amount from the reclaim queue using the idle balance of a VLF
   * @param vlfVault The address of the VLFVault
   * @param claimCount The amount of claim requests to resolve
   */
  function reserveVLF(address vlfVault, uint256 claimCount) external;

  /**
   * @notice Settles an yield generated from VLF Protocol
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the yield is settled
   * @param vlfVault The address of the VLFVault to be affected
   * @param amount The amount of yield to settle
   */
  function settleVLFYield(uint256 chainId, address vlfVault, uint256 amount) external;

  /**
   * @notice Settles a loss incurred by the VLF Protocol
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the loss is settled
   * @param vlfVault The address of the VLFVault to be affected
   * @param amount The amount of loss to settle
   */
  function settleVLFLoss(uint256 chainId, address vlfVault, uint256 amount) external;

  /**
   * @notice Settle extra rewards generated from VLF Protocol
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the rewards are settled
   * @param vlfVault The address of the VLFVault
   * @param branchReward The address of the reward asset on the branch chain
   * @param amount The amount of extra rewards to settle
   */
  function settleVLFExtraRewards(uint256 chainId, address vlfVault, address branchReward, uint256 amount) external;

  /**
   * @notice Initialize an asset for a given chain's MitosisVault
   * @param chainId The ID of the chain where the asset is initialized
   * @param hubAsset The address of the hub asset to initialize on the branch chain
   */
  function initializeAsset(uint256 chainId, address hubAsset) external payable;

  /**
   * @notice Sets the withdrawable deposit threshold for a specific asset on a given chain
   * @dev This threshold determines the minimum deposit required to be eligible for withdrawal.
   * @param chainId The ID of the chain where the threshold is being set
   * @param hubAsset The address of the hub asset for which the threshold applies
   * @param threshold The minimum deposit amount required for withdrawal
   */
  function setBranchLiquidityThreshold(uint256 chainId, address hubAsset, uint256 threshold) external;

  /**
   * @notice Sets the withdrawable deposit threshold for multiple assets across multiple chains
   * @param chainIds An array of chain IDs where the thresholds are being set
   * @param hubAssets An array of hub asset addresses for which the thresholds apply
   * @param thresholds An array of minimum deposit amounts required for withdrawal
   */
  function setBranchLiquidityThreshold(
    uint256[] calldata chainIds,
    address[] calldata hubAssets,
    uint256[] calldata thresholds
  ) external;

  /**
   * @notice Initialize a VLF for branch asset (VLF) on a given chain
   * @param chainId The ID of the chain where the VLF is initialized
   * @param vlfVault The address of the VLFVault to initialize
   */
  function initializeVLF(uint256 chainId, address vlfVault) external payable;

  /**
   * @notice Set an asset pair
   * @param hubAsset The address of the hub asset
   * @param branchChainId The ID of the branch chain
   * @param branchAsset The address of the branch asset
   * @param branchAssetDecimals The decimals of the branch asset
   */
  function setAssetPair(address hubAsset, uint256 branchChainId, address branchAsset, uint8 branchAssetDecimals)
    external;

  /**
   * @notice Set the entrypoint address
   * @param entrypoint_ The new entrypoint address
   */
  function setEntrypoint(address entrypoint_) external;

  /**
   * @notice Set the reclaim queue address
   * @param reclaimQueue_ The new reclaim queue address
   */
  function setReclaimQueue(address reclaimQueue_) external;

  /**
   * @notice Set the reward treasury address
   * @param treasury_ The new treasury address
   */
  function setTreasury(address treasury_) external;

  /**
   * @notice Set the hub asset factory address
   * @param hubAssetFactory_ The new hub asset factory address
   */
  function setHubAssetFactory(address hubAssetFactory_) external;

  /**
   * @notice Set the VLFVaultFactory address
   * @param vlfVaultFactory_ The new VLFVaultFactory address
   */
  function setVLFVaultFactory(address vlfVaultFactory_) external;

  /**
   * @notice Set the strategist for a VLF
   * @param vlfVault The address of the VLFVault
   * @param strategist The address of the new strategist
   */
  function setStrategist(address vlfVault, address strategist) external;
}
