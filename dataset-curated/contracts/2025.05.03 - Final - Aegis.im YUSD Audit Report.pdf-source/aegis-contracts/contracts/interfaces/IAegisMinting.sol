// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAegisMintingEvents {
  /// @dev Event emitted when YUSD is minted
  event Mint(address indexed userWallet, address collateralAsset, uint256 collateralAmount, uint256 yusdAmount, uint256 fee);

  /// @dev Event emitted when new RedeemRequest is created
  event CreateRedeemRequest(string requestId, address indexed userWallet, address collateralAsset, uint256 collateralAmount, uint256 yusdAmount);

  /// @dev Event emitted when RedeemRequest is approved and executed by funds manager
  event ApproveRedeemRequest(
    string requestId,
    address indexed manager,
    address indexed userWallet,
    address collateralAsset,
    uint256 collateralAmount,
    uint256 yusdAmount,
    uint256 fee
  );

  /// @dev Event emitted when RedeemRequest is rejected
  event RejectRedeemRequest(string requestId, address manager, address userWallet, uint256 yusdAmount);

  /// @dev Event emitted when expired redeem request is withdrawn by user
  event WithdrawRedeemRequest(string requestId, address userWallet, uint256 yusdAmount);

  /// @dev Event emitted when collateral asset income is deposited
  event DepositIncome(
    string snapshotId,
    address indexed manager,
    address collateralAsset,
    uint256 collateralAmount,
    uint256 yusdAmount,
    uint256 fee,
    uint256 timestamp
  );

  /// @dev Event emitted when collateral asset is transferred to custodian wallet
  event CustodyTransfer(address indexed wallet, address indexed asset, uint256 amount);

  /// @dev Event emitted when all collateral assets forcefully transferred to custodian wallet
  event ForceCustodyTransfer(address indexed wallet, address indexed asset, uint256 amount);

  /// @dev Event emitted when a supported asset is added
  event AssetAdded(address indexed asset, uint32 chainlinkHeartbeat);

  /// @dev Event emitted when a supported asset is removed
  event AssetRemoved(address indexed asset);

  /// @dev Event emitted when a custodian address is added
  event CustodianAddressAdded(address indexed custodian);

  /// @dev Event emitted when a custodian address is removed
  event CustodianAddressRemoved(address indexed custodian);

  /// @dev Event emitted when a AegisRewards contract address is changed
  event SetAegisRewardsAddress(address indexed rewards);

  /// @dev Event emitted when a AegisConfig contract address is changed
  event SetAegisConfigAddress(address indexed config);

  /// @dev Event emitted when a InsuranceFund address is changed
  event SetInsuranceFundAddress(address indexed insuranceFund);

  /// @dev Event emitted when a AegisOracle address is changed
  event SetAegisOracleAddress(address indexed oracle);

  /// @dev Event emitted when a fee percent of income minted YUSD is changed
  event SetIncomeFeeBP(uint16 percentPB);

  /// @dev Event emitted when mint is paused/unpaused
  event MintPauseChanged(bool paused);

  /// @dev Event emitted when redeem is paused/unpaused
  event RedeemPauseChanged(bool paused);

  /// @dev Event emitted when a fee percent of minted YUSD is changed
  event SetMintFeeBP(uint16 val);

  /// @dev Event emitted when a fee percent of redeemed YUSD is changed
  event SetRedeemFeeBP(uint16 val);

  /// @dev Event emitted when asset amount is frozen
  event FreezeFunds(address indexed asset, uint256 amount);

  /// @dev Event emitted when asset amount is unfrozen
  event UnfreezeFunds(address indexed asset, uint256 amount);

  /// @dev Event emitted when mint limit parameters are changed
  event SetMintLimits(uint32 periodDuration, uint256 maxPeriodAmount);

  /// @dev Event emitted when redeem limit parameters are changed
  event SetRedeemLimits(uint32 periodDuration, uint256 maxPeriodAmount);

  /// @dev Event emitted when Chainlink FeedRegistry address is changed
  event SetFeedRegistryAddress(address registry);

  /// @dev Event emitted when Chainlink asset feed heartbeat is changed
  event SetChainlinkAssetHeartbeat(address indexed asset, uint32 chainlinkHeartbeat);
}

interface IAegisMintingErrors {
  error ZeroAddress();
  error InvalidAddress();
  error InvalidAssetAddress(address asset);
  error InvalidCustodianAddress(address custodian);
  error InvalidOrder();
  error NotEnoughFunds();
  error InvalidPercentBP(uint256 value);
  error InvalidRedeemRequest();
  error NotAssetsProvided();
  error MintPaused();
  error RedeemPaused();
  error InvalidAmount();
  error LimitReached();
  error NotWhitelisted();
  error PriceSlippage();
  error InvalidNonce();
}
