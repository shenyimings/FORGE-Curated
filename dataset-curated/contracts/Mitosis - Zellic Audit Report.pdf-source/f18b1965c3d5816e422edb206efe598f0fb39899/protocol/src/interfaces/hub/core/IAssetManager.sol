// SPDX-License-Identifier: MIT
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
   * @notice Emitted when a new Matrix vault factory is set
   * @param matrixVaultFactory The address of the new Matrix vault factory
   */
  event MatrixVaultFactorySet(address indexed matrixVaultFactory);

  /**
   * @notice Emitted when a new EOL vault factory is set
   * @param eolVaultFactory The address of the new EOL vault factory
   */
  event EOLVaultFactorySet(address indexed eolVaultFactory);

  /**
   * @notice Emitted when a new strategist is set for a MatrixVault
   * @param matrixVault The address of the MatrixVault
   * @param strategist The address of the new strategist
   */
  event StrategistSet(address indexed matrixVault, address indexed strategist);

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

  error IAssetManagerStorageV1__MatrixVaultFactoryNotSet();
  error IAssetManagerStorageV1__InvalidMatrixVault(address matrixVault);
  error IAssetManagerStorageV1__MatrixNotInitialized(uint256 chainId, address matrixVault);
  error IAssetManagerStorageV1__MatrixAlreadyInitialized(uint256 chainId, address matrixVault);

  error IAssetManagerStorageV1__EOLVaultFactoryNotSet();
  error IAssetManagerStorageV1__InvalidEOLVault(address eolVault);
  error IAssetManagerStorageV1__EOLNotInitialized(uint256 chainId, address eolVault);
  error IAssetManagerStorageV1__EOLAlreadyInitialized(uint256 chainId, address eolVault);

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
   * @notice Get the current Matrix vault factory address (see IMatrixVaultFactory)
   */
  function matrixVaultFactory() external view returns (address);

  /**
   * @notice Get the current EOL vault factory address (see IEOLVaultFactory)
   */
  function eolVaultFactory() external view returns (address);

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
   * @notice Check if a MatrixVault is initialized for a given chain and branch asset (MatrixVault -> hubAsset -> branchAsset)
   * @param chainId The ID of the chain
   * @param matrixVault The address of the MatrixVault
   */
  function matrixInitialized(uint256 chainId, address matrixVault) external view returns (bool);

  /**
   * @notice Check if a EOL vault is initialized for a given chain and branch asset (EOLVault -> hubAsset -> branchAsset)
   * @param chainId The ID of the chain
   * @param eolVault The address of the EOL vault
   */
  function eolInitialized(uint256 chainId, address eolVault) external view returns (bool);

  /**
   * @notice Get the idle balance of a MatrixVault
   * @dev The idle balance will be calculated like this:
   * @dev (total supplied amount - total utilized amount - total pending reclaim amount)
   * @param matrixVault The address of the MatrixVault
   */
  function matrixIdle(address matrixVault) external view returns (uint256);

  /**
   * @notice Get the total utilized balance (hubAsset/branchAsset) of a MatrixVault
   * @param matrixVault The address of the MatrixVault
   */
  function matrixAlloc(address matrixVault) external view returns (uint256);

  /**
   * @notice Get the strategist address for a MatrixVault
   * @param matrixVault The address of the MatrixVault
   */
  function strategist(address matrixVault) external view returns (address);
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
   */
  event AssetInitialized(address indexed hubAsset, uint256 indexed chainId, address branchAsset);

  /**
   * @notice Emitted when a MatrixVault is initialized
   * @param hubAsset The address of the hub asset
   * @param chainId The ID of the chain where the MatrixVault is initialized
   * @param matrixVault The address of the initialized MatrixVault
   * @param branchAsset The address of the branch asset associated with the MatrixVault
   */
  event MatrixInitialized(address indexed hubAsset, uint256 indexed chainId, address matrixVault, address branchAsset);

  /**
   * @notice Emitted when a EOL vault is initialized
   * @param hubAsset The address of the hub asset
   * @param chainId The ID of the chain where the EOL vault is initialized
   * @param eolVault The address of the initialized EOL vault
   * @param branchAsset The address of the branch asset associated with the EOL vault
   */
  event EOLInitialized(address indexed hubAsset, uint256 indexed chainId, address eolVault, address branchAsset);

  /**
   * @notice Emitted when a deposit is made
   * @param chainId The ID of the chain where the deposit is made
   * @param hubAsset The address of the asset that correspond to the branch asset
   * @param to The address receiving the hubAsset
   * @param amount The amount deposited
   */
  event Deposited(uint256 indexed chainId, address indexed hubAsset, address indexed to, uint256 amount);

  /**
   * @notice Emitted when a deposit is made with supply to a MatrixVault
   * @param chainId The ID of the chain where the deposit is made
   * @param hubAsset The address of the asset that correspond to the branch asset
   * @param to The address receiving the miAsset
   * @param matrixVault The address of the MatrixVault supplied into
   * @param amount The amount deposited
   * @param supplyAmount The amount supplied into the MatrixVault
   */
  event DepositedWithSupplyMatrix(
    uint256 indexed chainId,
    address indexed hubAsset,
    address indexed to,
    address matrixVault,
    uint256 amount,
    uint256 supplyAmount
  );

  /**
   * @notice Emitted when a deposit is made with supply to a EOL vault
   * @param chainId The ID of the chain where the deposit is made
   * @param hubAsset The address of the asset that correspond to the branch asset
   * @param to The address receiving the miAsset
   * @param eolVault The address of the EOL vault supplied into
   * @param amount The amount deposited
   * @param supplyAmount The amount supplied into the EOL vault
   */
  event DepositedWithSupplyEOL(
    uint256 indexed chainId,
    address indexed hubAsset,
    address indexed to,
    address eolVault,
    uint256 amount,
    uint256 supplyAmount
  );

  /**
   * @notice Emitted when hubAssets are withdrawn
   * @param chainId The ID of the chain where the withdrawal occurs
   * @param hubAsset The address of the withdrawn asset
   * @param to The address receiving the withdrawn assets on the branch chain
   * @param amount The hubAsset amount to be withdrawn
   */
  event Withdrawn(uint256 indexed chainId, address indexed hubAsset, address indexed to, uint256 amount);

  /**
   * @notice Emitted when a reward is settled from the branch chain to the hub chain for a specific MatrixVault
   * @param chainId The ID of the chain where the reward is reported
   * @param matrixVault The address of the MatrixVault receiving the reward
   * @param asset The address of the reward asset
   * @param amount The amount of the reward
   */
  event MatrixRewardSettled(
    uint256 indexed chainId, address indexed matrixVault, address indexed asset, uint256 amount
  );

  /**
   * @notice Emitted when a loss is settled from the branch chain to the hub chain for a specific MatrixVault
   * @param chainId The ID of the chain where the loss is reported
   * @param matrixVault The address of the MatrixVault incurring the loss
   * @param asset The address of the asset lost
   * @param amount The amount of the loss
   */
  event MatrixLossSettled(uint256 indexed chainId, address indexed matrixVault, address indexed asset, uint256 amount);

  /**
   * @notice Emitted when assets are allocated to the branch chain for a specific MatrixVault
   * @param strategist The address of the strategist
   * @param chainId The ID of the chain where the allocation occurs
   * @param matrixVault The address of the MatrixVault to be reported the allocation
   * @param amount The amount allocated
   */
  event MatrixAllocated(
    address indexed strategist, uint256 indexed chainId, address indexed matrixVault, uint256 amount
  );

  /**
   * @notice Emitted when assets are deallocated from the branch chain for a specific MatrixVault
   * @param chainId The ID of the chain where the deallocation occurs
   * @param matrixVault The address of the MatrixVault to be reported the deallocation
   * @param amount The amount deallocated
   */
  event MatrixDeallocated(uint256 indexed chainId, address indexed matrixVault, uint256 amount);

  /**
   * @notice Emitted when a claim request is reserved from the reclaim queue
   * @param strategist The address of the strategist
   * @param matrixVault The address of the MatrixVault to be reported the claim request
   * @param claimCount The amount of the claim request
   * @param totalReservedShares The total amount of shares reserved
   * @param totalReservedAssets The total amount of assets reserved
   */
  event MatrixReserved(
    address indexed strategist,
    address indexed matrixVault,
    uint256 claimCount,
    uint256 totalReservedShares,
    uint256 totalReservedAssets
  );

  /**
   * @notice Emitted when an asset pair is set
   * @param hubAsset The address of the hub asset
   * @param branchChainId The ID of the branch chain
   * @param branchAsset The address of the branch asset
   */
  event AssetPairSet(address hubAsset, uint256 branchChainId, address branchAsset);

  /**
   * @notice Error thrown when a MatrixVault has no claimable amount
   * @param matrixVault The address of the MatrixVault with no claimable amount
   */
  error IAssetManager__NothingToReserve(address matrixVault);

  /**
   * @notice Error thrown when a MatrixVault has insufficient funds
   * @param matrixVault The address of the MatrixVault with insufficient funds
   */
  error IAssetManager__MatrixInsufficient(address matrixVault);

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
   * @notice Deposit branch assets with supply to a MatrixVault
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the deposit is made
   * @param branchAsset The address of the branch asset being deposited
   * @param to The address receiving the deposit
   * @param matrixVault The address of the MatrixVault to supply into
   * @param amount The amount to deposit
   */
  function depositWithSupplyMatrix(
    uint256 chainId,
    address branchAsset,
    address to,
    address matrixVault,
    uint256 amount
  ) external;

  /**
   * @notice Deposit branch assets with supply to a EOL vault
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the deposit is made
   * @param branchAsset The address of the branch asset being deposited
   * @param to The address receiving the deposit
   * @param eolVault The address of the EOL vault to supply into
   * @param amount The amount to deposit
   */
  function depositWithSupplyEOL(uint256 chainId, address branchAsset, address to, address eolVault, uint256 amount)
    external;

  /**
   * @notice Withdraw hub assets and receive the asset on the branch chain
   * @dev Dispatches the cross-chain message to branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the withdrawal occurs
   * @param hubAsset The address of the hub asset to withdraw
   * @param to The address receiving the withdrawn assets
   * @param amount The amount to withdraw
   */
  function withdraw(uint256 chainId, address hubAsset, address to, uint256 amount) external;

  /**
   * @notice Allocate the assets to the branch chain for a specific MatrixVault
   * @dev Only the strategist of the MatrixVault can allocate assets
   * @dev Dispatches the cross-chain message to branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the allocation occurs
   * @param matrixVault The address of the MatrixVault to be affected
   * @param amount The amount to allocate
   */
  function allocateMatrix(uint256 chainId, address matrixVault, uint256 amount) external;

  /**
   * @notice Deallocate the assets from the branch chain for a specific MatrixVault
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the deallocation occurs
   * @param matrixVault The address of the MatrixVault to be affected
   * @param amount The amount to deallocate
   */
  function deallocateMatrix(uint256 chainId, address matrixVault, uint256 amount) external;

  /**
   * @notice Resolves the pending reclaim request amount from the reclaim queue using the idle balance of a MatrixVault
   * @param matrixVault The address of the MatrixVault
   * @param claimCount The amount of claim requests to resolve
   */
  function reserveMatrix(address matrixVault, uint256 claimCount) external;

  /**
   * @notice Settles an yield generated from Matrix Protocol
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the yield is settled
   * @param matrixVault The address of the MatrixVault to be affected
   * @param amount The amount of yield to settle
   */
  function settleMatrixYield(uint256 chainId, address matrixVault, uint256 amount) external;

  /**
   * @notice Settles a loss incurred by the Matrix Protocol
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the loss is settled
   * @param matrixVault The address of the MatrixVault to be affected
   * @param amount The amount of loss to settle
   */
  function settleMatrixLoss(uint256 chainId, address matrixVault, uint256 amount) external;

  /**
   * @notice Settle extra rewards generated from Matrix Protocol
   * @dev Processes the cross-chain message from the branch chain (see IAssetManagerEntrypoint)
   * @param chainId The ID of the chain where the rewards are settled
   * @param matrixVault The address of the MatrixVault
   * @param branchReward The address of the reward asset on the branch chain
   * @param amount The amount of extra rewards to settle
   */
  function settleMatrixExtraRewards(uint256 chainId, address matrixVault, address branchReward, uint256 amount)
    external;

  /**
   * @notice Initialize an asset for a given chain's MitosisVault
   * @param chainId The ID of the chain where the asset is initialized
   * @param hubAsset The address of the hub asset to initialize on the branch chain
   */
  function initializeAsset(uint256 chainId, address hubAsset) external;

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
   * @notice Initialize a Matrix for branch asset (MatrixVault) on a given chain
   * @param chainId The ID of the chain where the MatrixVault is initialized
   * @param matrixVault The address of the MatrixVault to initialize
   */
  function initializeMatrix(uint256 chainId, address matrixVault) external;

  /**
   * @notice Initialize a EOL vault for branch asset on a given chain
   * @param chainId The ID of the chain where the EOL vault is initialized
   * @param eolVault The address of the EOL vault to initialize
   */
  function initializeEOL(uint256 chainId, address eolVault) external;

  /**
   * @notice Set an asset pair
   * @param hubAsset The address of the hub asset
   * @param branchChainId The ID of the branch chain
   * @param branchAsset The address of the branch asset
   */
  function setAssetPair(address hubAsset, uint256 branchChainId, address branchAsset) external;

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
   * @notice Set the Matrix vault factory address
   * @param matrixVaultFactory_ The new Matrix vault factory address
   */
  function setMatrixVaultFactory(address matrixVaultFactory_) external;

  /**
   * `
   * @notice Set the EOL vault factory address
   * @param eolVaultFactory_ The new EOL vault factory address
   */
  function setEOLVaultFactory(address eolVaultFactory_) external;

  /**
   * @notice Set the strategist for a MatrixVault
   * @param matrixVault The address of the MatrixVault
   * @param strategist The address of the new strategist
   */
  function setStrategist(address matrixVault, address strategist) external;
}
