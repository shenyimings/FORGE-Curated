// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { FeedRegistryInterface } from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";

import { OrderLib } from "./lib/OrderLib.sol";

import { IAegisMintingEvents, IAegisMintingErrors } from "./interfaces/IAegisMinting.sol";
import { IAegisRewards } from "./interfaces/IAegisRewards.sol";
import { IAegisConfig } from "./interfaces/IAegisConfig.sol";
import { IAegisOracle } from "./interfaces/IAegisOracle.sol";
import { IYUSD } from "./interfaces/IYUSD.sol";

contract AegisMinting is IAegisMintingEvents, IAegisMintingErrors, AccessControlDefaultAdminRules, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using OrderLib for OrderLib.Order;
  using SafeERC20 for IERC20;
  using SafeERC20 for IYUSD;

  enum RedeemRequestStatus {
    PENDING,
    APPROVED,
    REJECTED,
    WITHDRAWN
  }

  struct RedeemRequest {
    RedeemRequestStatus status;
    OrderLib.Order order;
    uint256 timestamp;
  }

  struct MintRedeemLimit {
    uint32 periodDuration;
    uint32 currentPeriodStartTime;
    uint256 maxPeriodAmount;
    uint256 currentPeriodTotalAmount;
  }

  uint16 constant MAX_BPS = 10_000;

  /// @dev role enabling to update various settings
  bytes32 private constant SETTINGS_MANAGER_ROLE = keccak256("SETTINGS_MANAGER_ROLE");

  /// @dev role enabling to deposit income/redeem and withdraw redeem
  bytes32 private constant FUNDS_MANAGER_ROLE = keccak256("FUNDS_MANAGER_ROLE");

  /// @dev role enabling to transfer collateral to custody wallets
  bytes32 private constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

  /// @dev EIP712 domain
  bytes32 private constant EIP712_DOMAIN = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  /// @dev EIP712 name
  bytes32 private constant EIP712_NAME = keccak256("AegisMinting");

  /// @dev holds EIP712 revision
  bytes32 private constant EIP712_REVISION = keccak256("1");

  /// @dev YUSD stablecoin
  IYUSD public immutable yusd;

  /// @dev AegisRewards contract
  IAegisRewards public aegisRewards;

  /// @dev AegisConfig contract
  IAegisConfig public aegisConfig;

  /// @dev AegisOracle contract providing YUSD/USD price
  IAegisOracle public aegisOracle;

  /// @dev InsuranceFund address
  address public insuranceFundAddress;

  /// @dev Percent of YUSD rewards that will be transferred to InsuranceFund address. Default: 5%
  uint16 public incomeFeeBP = 500;

  /// @dev Mint pause state
  bool public mintPaused;

  /// @dev Redeem pause state
  bool public redeemPaused;

  /// @dev Percent of YUSD that will be taken as a fee from mint amount
  uint16 public mintFeeBP;

  /// @dev Percent of YUSD that will be taken as a fee from redeem amount
  uint16 public redeemFeeBP;

  /// @dev Asset funds that were frozen and cannot be transfered to custody
  mapping(address => uint256) public assetFrozenFunds;

  /// @dev Mint limiting parameter
  MintRedeemLimit public mintLimit;

  /// @dev Redeem limiting parameters
  MintRedeemLimit public redeemLimit;

  /// @dev Tracks total amount of users locked YUSD for redeem requests
  uint256 public totalRedeemLockedYUSD;

  /// @dev Asset heartbeat of Chainlink feed in seconds
  mapping(address => uint32) public chainlinkAssetHeartbeat;

  /// @dev Chainlink FeedRegistry
  FeedRegistryInterface private _feedRegistry;

  /// @dev Supported assets
  EnumerableSet.AddressSet private _supportedAssets;

  /// @dev Custodian addresses
  EnumerableSet.AddressSet private _custodianAddresses;

  mapping(address => uint256) private _custodyTransferrableAssetFunds;

  /// @dev Map of redeem request id to RedeemRequest struct
  mapping(bytes32 => RedeemRequest) private _redeemRequests;

  /// @dev holds computable chain id
  uint256 private immutable _chainId;

  /// @dev holds computable domain separator
  bytes32 private immutable _domainSeparator;

  /// @dev user order deduplication
  mapping(address => mapping(uint256 => uint256)) private _orderBitmaps;

  modifier onlyWhitelisted(address sender) {
    if (!aegisConfig.isWhitelisted(sender)) {
      revert NotWhitelisted();
    }
    _;
  }

  modifier onlySupportedAsset(address asset) {
    if (!_supportedAssets.contains(asset)) {
      revert InvalidAssetAddress(asset);
    }
    _;
  }

  modifier onlyCustodianAddress(address wallet) {
    if (!_custodianAddresses.contains(wallet)) {
      revert InvalidCustodianAddress(wallet);
    }
    _;
  }

  modifier whenRedeemUnpaused() {
    if (redeemPaused) {
      revert RedeemPaused();
    }
    _;
  }

  constructor(
    IYUSD _yusd,
    IAegisConfig _aegisConfig,
    IAegisRewards _aegisRewards,
    IAegisOracle _aegisOracle,
    FeedRegistryInterface _fdRegistry,
    address _insuranceFundAddress,
    address[] memory _assets,
    uint32[] memory _chainlinkAssetHeartbeats,
    address[] memory _custodians,
    address _admin
  ) AccessControlDefaultAdminRules(3 days, _admin) {
    if (address(_yusd) == address(0)) revert ZeroAddress();
    if (address(_aegisRewards) == address(0)) revert ZeroAddress();
    if (address(_aegisConfig) == address(0)) revert ZeroAddress();
    if (_assets.length == 0) revert NotAssetsProvided();
    require(_assets.length == _chainlinkAssetHeartbeats.length);

    yusd = _yusd;
    mintLimit.currentPeriodStartTime = uint32(block.timestamp);
    redeemLimit.currentPeriodStartTime = uint32(block.timestamp);
    _setAegisRewardsAddress(_aegisRewards);
    _setAegisConfigAddress(_aegisConfig);
    _setFeedRegistryAddress(_fdRegistry);
    _setAegisOracleAddress(_aegisOracle);
    _setInsuranceFundAddress(_insuranceFundAddress);

    for (uint256 i = 0; i < _assets.length; i++) {
      _addSupportedAsset(_assets[i], _chainlinkAssetHeartbeats[i]);
    }

    for (uint256 i = 0; i < _custodians.length; i++) {
      _addCustodianAddress(_custodians[i]);
    }

    _chainId = block.chainid;
    _domainSeparator = _computeDomainSeparator();
  }

  /// @dev Returns custody transferrable asset funds minus durty funds
  function custodyAvailableAssetBalance(address asset) public view returns (uint256) {
    return _custodyAvailableAssetBalance(asset);
  }

  /// @dev Returns asset balance minus custody transferrable and durty funds
  function untrackedAvailableAssetBalance(address asset) public view returns (uint256) {
    return _untrackedAvailableAssetBalance(asset);
  }

  /// @dev Returns RedeemRequest by id
  function getRedeemRequest(string calldata requestId) public view returns (RedeemRequest memory) {
    return _redeemRequests[keccak256(abi.encode(requestId))];
  }

  /// @dev Retuns asset/USD price from Chainlink feed
  function assetChainlinkUSDPrice(address asset) public view returns (uint256) {
    (uint256 price, ) = _getAssetUSDPriceChainlink(asset);
    return price;
  }

  /// @dev Returns asset/YUSD price from AegisOracle
  function assetAegisOracleYUSDPrice(address asset) public view returns (uint256) {
    (uint256 price, ) = _getAssetYUSDPriceOracle(asset);
    return price;
  }

  /**
   * @dev Mints YUSD from assets
   * @param order Struct containing order details
   * @param signature Signature of trusted signer
   */
  function mint(
    OrderLib.Order calldata order,
    bytes calldata signature
  ) external nonReentrant onlyWhitelisted(order.userWallet) onlySupportedAsset(order.collateralAsset) {
    if (mintPaused) {
      revert MintPaused();
    }
    if (order.orderType != OrderLib.OrderType.MINT) {
      revert InvalidOrder();
    }

    _checkMintRedeemLimit(mintLimit, order.yusdAmount);
    order.verify(getDomainSeparator(), aegisConfig.trustedSigner(), signature);
    _deduplicateOrder(order.userWallet, order.nonce);

    uint256 yusdAmount = _calculateMinYUSDAmount(order.collateralAsset, order.collateralAmount, order.yusdAmount);
    if (yusdAmount < order.slippageAdjustedAmount) {
      revert PriceSlippage();
    }

    // Take a fee, if it's applicable
    (uint256 mintAmount, uint256 fee) = _calculateInsuranceFundFeeFromAmount(yusdAmount, mintFeeBP);
    if (fee > 0) {
      yusd.mint(insuranceFundAddress, fee);
    }

    IERC20(order.collateralAsset).safeTransferFrom(order.userWallet, address(this), order.collateralAmount);
    yusd.mint(order.userWallet, mintAmount);
    _custodyTransferrableAssetFunds[order.collateralAsset] += order.collateralAmount;

    emit Mint(_msgSender(), order.collateralAsset, order.collateralAmount, mintAmount, fee);
  }

  /**
   * @dev Creates new RedeemRequest and locks user's YUSD tokens
   * @param order Struct containing order details
   * @param signature Signature of trusted signer
   */
  function requestRedeem(
    OrderLib.Order calldata order,
    bytes calldata signature
  ) external nonReentrant onlyWhitelisted(order.userWallet) whenRedeemUnpaused onlySupportedAsset(order.collateralAsset) {
    if (order.orderType != OrderLib.OrderType.REDEEM) {
      revert InvalidOrder();
    }

    _checkMintRedeemLimit(redeemLimit, order.yusdAmount);
    order.verify(getDomainSeparator(), aegisConfig.trustedSigner(), signature);

    uint256 collateralAmount = _calculateRedeemMinCollateralAmount(order.collateralAsset, order.collateralAmount, order.yusdAmount);
    // Revert transaction when smallest amount is less than order minAmount
    if (collateralAmount < order.slippageAdjustedAmount) {
      revert PriceSlippage();
    }

    string memory requestId = abi.decode(order.additionalData, (string));
    RedeemRequest memory request = _redeemRequests[keccak256(abi.encode(requestId))];
    if (request.timestamp != 0) {
      revert InvalidRedeemRequest();
    }

    _redeemRequests[keccak256(abi.encode(requestId))] = RedeemRequest(RedeemRequestStatus.PENDING, order, block.timestamp);

    // Lock YUSD
    yusd.safeTransferFrom(order.userWallet, address(this), order.yusdAmount);
    totalRedeemLockedYUSD += order.yusdAmount;

    emit CreateRedeemRequest(requestId, _msgSender(), order.collateralAsset, order.collateralAmount, order.yusdAmount);
  }

  /**
   * @dev Approves pending RedeemRequest.
   * @dev Burns locked YUSD and transfers collateral amount to request order benefactor
   * @param requestId Id of RedeemRequest to approve
   * @param amount Max collateral amount that will be transferred to user
   */
  function approveRedeemRequest(string calldata requestId, uint256 amount) external nonReentrant onlyRole(FUNDS_MANAGER_ROLE) whenRedeemUnpaused {
    RedeemRequest storage request = _redeemRequests[keccak256(abi.encode(requestId))];
    if (request.timestamp == 0 || request.status != RedeemRequestStatus.PENDING) {
      revert InvalidRedeemRequest();
    }
    if (amount == 0 || amount > request.order.collateralAmount) {
      revert InvalidAmount();
    }

    uint256 collateralAmount = _calculateRedeemMinCollateralAmount(request.order.collateralAsset, amount, request.order.yusdAmount);
    /*
     * Reject if:
     * - asset is no longer supported
     * - smallest amount is less than order minAmount
     * - order expired
     */
    if (
      !_supportedAssets.contains(request.order.collateralAsset) ||
      collateralAmount < request.order.slippageAdjustedAmount ||
      request.order.expiry < block.timestamp
    ) {
      _rejectRedeemRequest(requestId, request);
      return;
    }

    uint256 availableAssetFunds = _untrackedAvailableAssetBalance(request.order.collateralAsset);
    if (availableAssetFunds < collateralAmount) {
      revert NotEnoughFunds();
    }

    // Take a fee, if it's applicable
    (uint256 burnAmount, uint256 fee) = _calculateInsuranceFundFeeFromAmount(request.order.yusdAmount, redeemFeeBP);
    if (fee > 0) {
      yusd.safeTransfer(insuranceFundAddress, fee);
    }

    request.status = RedeemRequestStatus.APPROVED;
    totalRedeemLockedYUSD -= request.order.yusdAmount;

    IERC20(request.order.collateralAsset).safeTransfer(request.order.userWallet, collateralAmount);
    yusd.burn(burnAmount);

    emit ApproveRedeemRequest(requestId, _msgSender(), request.order.userWallet, request.order.collateralAsset, collateralAmount, burnAmount, fee);
  }

  /**
   * @dev Rejects pending RedeemRequest and unlocks user's YUSD
   * @param requestId Id of RedeemRequest to reject
   */
  function rejectRedeemRequest(string calldata requestId) external nonReentrant onlyRole(FUNDS_MANAGER_ROLE) whenRedeemUnpaused {
    RedeemRequest storage request = _redeemRequests[keccak256(abi.encode(requestId))];
    if (request.timestamp == 0 || request.status != RedeemRequestStatus.PENDING) {
      revert InvalidRedeemRequest();
    }

    _rejectRedeemRequest(requestId, request);
  }

  /**
   * @dev Withdraws expired RedeemRequest locked YUSD funds to user
   * @param requestId Id of RedeemRequest to withdraw
   */
  function withdrawRedeemRequest(string calldata requestId) public nonReentrant whenRedeemUnpaused {
    RedeemRequest storage request = _redeemRequests[keccak256(abi.encode(requestId))];
    if (request.timestamp == 0 || request.status != RedeemRequestStatus.PENDING || request.order.expiry > block.timestamp) {
      revert InvalidRedeemRequest();
    }

    request.status = RedeemRequestStatus.WITHDRAWN;

    // Unlock YUSD
    totalRedeemLockedYUSD -= request.order.yusdAmount;
    yusd.safeTransfer(request.order.userWallet, request.order.yusdAmount);

    emit WithdrawRedeemRequest(requestId, request.order.userWallet, request.order.yusdAmount);
  }

  /**
   * @dev Mints YUSD rewards in exchange for collateral asset income
   * @param order Struct containing order details
   * @param signature Signature of trusted signer
   */
  function depositIncome(
    OrderLib.Order calldata order,
    bytes calldata signature
  ) external nonReentrant onlyRole(FUNDS_MANAGER_ROLE) onlySupportedAsset(order.collateralAsset) {
    if (order.orderType != OrderLib.OrderType.DEPOSIT_INCOME) {
      revert InvalidOrder();
    }
    order.verify(getDomainSeparator(), aegisConfig.trustedSigner(), signature);
    _deduplicateOrder(order.userWallet, order.nonce);

    uint256 availableAssetFunds = _untrackedAvailableAssetBalance(order.collateralAsset);
    if (availableAssetFunds < order.collateralAmount) {
      revert NotEnoughFunds();
    }

    uint256 yusdAmount = _calculateMinYUSDAmount(order.collateralAsset, order.collateralAmount, order.yusdAmount);

    _custodyTransferrableAssetFunds[order.collateralAsset] += order.collateralAmount;

    // Transfer percent of YUSD rewards to insurance fund
    (uint256 mintAmount, uint256 fee) = _calculateInsuranceFundFeeFromAmount(yusdAmount, incomeFeeBP);
    if (fee > 0) {
      yusd.mint(insuranceFundAddress, fee);
    }

    // Mint YUSD rewards to AegisRewards contract
    yusd.mint(address(aegisRewards), mintAmount);
    aegisRewards.depositRewards(order.additionalData, mintAmount);

    emit DepositIncome(
      abi.decode(order.additionalData, (string)),
      _msgSender(),
      order.collateralAsset,
      order.collateralAmount,
      mintAmount,
      fee,
      block.timestamp
    );
  }

  /**
   * @dev Transfers provided amount of asset to custodian wallet
   * @param wallet Custodian address
   * @param asset Asset address to transfer
   * @param amount Asset amount to transfer
   */
  function transferToCustody(
    address wallet,
    address asset,
    uint256 amount
  ) external nonReentrant onlyRole(COLLATERAL_MANAGER_ROLE) onlySupportedAsset(asset) onlyCustodianAddress(wallet) {
    uint256 availableBalance = _custodyAvailableAssetBalance(asset);
    if (availableBalance < amount) {
      revert NotEnoughFunds();
    }

    _custodyTransferrableAssetFunds[asset] -= amount;
    IERC20(asset).safeTransfer(wallet, amount);

    emit CustodyTransfer(wallet, asset, amount);
  }

  /**
   * @dev Forcefully transfers all asset funds except frozen
   * @param wallet Custodian address
   * @param asset Asset address to transfer
   */
  function forceTransferToCustody(
    address wallet,
    address asset
  ) external nonReentrant onlyRole(COLLATERAL_MANAGER_ROLE) onlySupportedAsset(asset) onlyCustodianAddress(wallet) {
    uint256 availableBalance = _custodyAvailableAssetBalance(asset);
    if (availableBalance == 0) {
      revert NotEnoughFunds();
    }

    _custodyTransferrableAssetFunds[asset] -= availableBalance;
    IERC20(asset).safeTransfer(wallet, availableBalance);

    emit ForceCustodyTransfer(wallet, asset, availableBalance);
  }

  /// @dev Sets new AegisRewards address
  function setAegisRewardsAddress(IAegisRewards _aegisRewards) external onlyRole(SETTINGS_MANAGER_ROLE) {
    if (address(_aegisRewards) == address(0)) {
      revert ZeroAddress();
    }
    _setAegisRewardsAddress(_aegisRewards);
  }

  /// @dev Sets new AegisConfig address
  function setAegisConfigAddress(IAegisConfig _config) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _setAegisConfigAddress(_config);
  }

  /// @dev Sets new InsuranceFund address
  function setInsuranceFundAddress(address _insuranceFundAddress) external onlyRole(SETTINGS_MANAGER_ROLE) {
    if (_insuranceFundAddress == address(this)) {
      revert InvalidAddress();
    }
    _setInsuranceFundAddress(_insuranceFundAddress);
  }

  /// @dev Sets new FeedRegistry address
  function setFeedRegistryAddress(FeedRegistryInterface _registry) external onlyRole(SETTINGS_MANAGER_ROLE) {
    _setFeedRegistryAddress(_registry);
  }

  /// @dev Sets new AegisOracle address
  function setAegisOracleAddress(IAegisOracle _aegisOracle) external onlyRole(SETTINGS_MANAGER_ROLE) {
    _setAegisOracleAddress(_aegisOracle);
  }

  /// @dev Sets percent in basis points of YUSD that will be taken as a fee on depositIncome
  function setIncomeFeeBP(uint16 value) external onlyRole(SETTINGS_MANAGER_ROLE) {
    // No more than 50%
    if (value > MAX_BPS / 2) {
      revert InvalidPercentBP(value);
    }
    incomeFeeBP = value;
    emit SetIncomeFeeBP(value);
  }

  /// @dev Switches mint pause state
  function setMintPaused(bool paused) external onlyRole(SETTINGS_MANAGER_ROLE) {
    mintPaused = paused;
    emit MintPauseChanged(paused);
  }

  /// @dev Swtiches redeem pause state
  function setRedeemPaused(bool paused) external onlyRole(SETTINGS_MANAGER_ROLE) {
    redeemPaused = paused;
    emit RedeemPauseChanged(paused);
  }

  /// @dev Sets percent in basis points of YUSD that will be taken as a fee on mint
  function setMintFeeBP(uint16 value) external onlyRole(SETTINGS_MANAGER_ROLE) {
    // No more than 50%
    if (value > MAX_BPS / 2) {
      revert InvalidPercentBP(value);
    }
    mintFeeBP = value;
    emit SetMintFeeBP(value);
  }

  /// @dev Sets percent in basis points of YUSD that will be taken as a fee on redeem
  function setRedeemFeeBP(uint16 value) external onlyRole(SETTINGS_MANAGER_ROLE) {
    // No more than 50%
    if (value > MAX_BPS / 2) {
      revert InvalidPercentBP(value);
    }
    redeemFeeBP = value;
    emit SetRedeemFeeBP(value);
  }

  /// @dev Sets mint limit period duration and maximum amount
  function setMintLimits(uint32 periodDuration, uint256 maxPeriodAmount) external onlyRole(SETTINGS_MANAGER_ROLE) {
    mintLimit.periodDuration = periodDuration;
    mintLimit.maxPeriodAmount = maxPeriodAmount;
    emit SetMintLimits(periodDuration, maxPeriodAmount);
  }

  /// @dev Sets redeem limit period duration and maximum amount
  function setRedeemLimits(uint32 periodDuration, uint256 maxPeriodAmount) external onlyRole(SETTINGS_MANAGER_ROLE) {
    redeemLimit.periodDuration = periodDuration;
    redeemLimit.maxPeriodAmount = maxPeriodAmount;
    emit SetRedeemLimits(periodDuration, maxPeriodAmount);
  }

  /// @dev Sets Chainlink feed heartbeat for asset
  function setChainlinkAssetHeartbeat(address asset, uint32 heartbeat) external onlyRole(SETTINGS_MANAGER_ROLE) onlySupportedAsset(asset) {
    chainlinkAssetHeartbeat[asset] = heartbeat;
    emit SetChainlinkAssetHeartbeat(asset, heartbeat);
  }

  /// @dev Adds an asset to supporetd assets list
  function addSupportedAsset(address asset, uint32 hearbeat) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _addSupportedAsset(asset, hearbeat);
  }

  /// @dev Removes an asset from supported assets list
  function removeSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (!_supportedAssets.remove(asset)) {
      revert InvalidAssetAddress(asset);
    }
    chainlinkAssetHeartbeat[asset] = 0;
    emit AssetRemoved(asset);
  }

  /// @dev Checks if an asset is supported
  function isSupportedAsset(address asset) public view returns (bool) {
    return _supportedAssets.contains(asset);
  }

  /// @dev Adds custodian to custodians address list
  function addCustodianAddress(address custodian) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _addCustodianAddress(custodian);
  }

  /// @dev Removes custodian from custodians address list
  function removeCustodianAddress(address custodian) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (!_custodianAddresses.remove(custodian)) {
      revert InvalidCustodianAddress(custodian);
    }
    emit CustodianAddressRemoved(custodian);
  }

  /// @dev Freeze asset funds and prevent them from transferring to custodians or users
  function freezeFunds(address asset, uint256 amount) external onlyRole(FUNDS_MANAGER_ROLE) onlySupportedAsset(asset) {
    if (assetFrozenFunds[asset] + amount > IERC20(asset).balanceOf(address(this))) {
      revert InvalidAmount();
    }

    assetFrozenFunds[asset] += amount;

    emit FreezeFunds(asset, amount);
  }

  /// @dev Unfreeze asset funds and allow them for transferring to custodians or users
  function unfreezeFunds(address asset, uint256 amount) external onlyRole(FUNDS_MANAGER_ROLE) onlySupportedAsset(asset) {
    if (amount > assetFrozenFunds[asset]) {
      revert InvalidAmount();
    }

    assetFrozenFunds[asset] -= amount;

    emit UnfreezeFunds(asset, amount);
  }

  /// @dev Return cached value if chainId matches cache, otherwise recomputes separator
  /// @return The domain separator at current chain
  function getDomainSeparator() public view returns (bytes32) {
    if (block.chainid == _chainId) {
      return _domainSeparator;
    }
    return _computeDomainSeparator();
  }

  /// @dev verify validity of nonce by checking its presence
  function verifyNonce(address sender, uint256 nonce) public view returns (uint256, uint256, uint256) {
    if (nonce == 0) revert InvalidNonce();
    uint256 invalidatorSlot = uint64(nonce) >> 8;
    uint256 invalidatorBit = 1 << uint8(nonce);
    uint256 invalidator = _orderBitmaps[sender][invalidatorSlot];
    if (invalidator & invalidatorBit != 0) revert InvalidNonce();

    return (invalidatorSlot, invalidator, invalidatorBit);
  }

  /// @dev deduplication of user order
  function _deduplicateOrder(address sender, uint256 nonce) private {
    (uint256 invalidatorSlot, uint256 invalidator, uint256 invalidatorBit) = verifyNonce(sender, nonce);
    _orderBitmaps[sender][invalidatorSlot] = invalidator | invalidatorBit;
  }

  function _addSupportedAsset(address asset, uint32 heartbeat) internal {
    if (asset == address(0) || asset == address(yusd) || !_supportedAssets.add(asset)) {
      revert InvalidAssetAddress(asset);
    }
    chainlinkAssetHeartbeat[asset] = heartbeat;
    emit AssetAdded(asset, heartbeat);
  }

  function _addCustodianAddress(address custodian) internal {
    if (custodian == address(0) || custodian == address(yusd) || !_custodianAddresses.add(custodian)) {
      revert InvalidCustodianAddress(custodian);
    }
    emit CustodianAddressAdded(custodian);
  }

  function _setInsuranceFundAddress(address _insuranceFundAddress) internal {
    insuranceFundAddress = _insuranceFundAddress;
    emit SetInsuranceFundAddress(insuranceFundAddress);
  }

  function _setAegisRewardsAddress(IAegisRewards _aegisRewards) internal {
    aegisRewards = _aegisRewards;
    emit SetAegisRewardsAddress(address(aegisRewards));
  }

  function _setAegisOracleAddress(IAegisOracle _aegisOracle) internal {
    aegisOracle = _aegisOracle;
    emit SetAegisOracleAddress(address(aegisOracle));
  }

  function _setAegisConfigAddress(IAegisConfig _config) internal {
    if (address(_config) != address(0) && !IERC165(address(_config)).supportsInterface(type(IAegisConfig).interfaceId)) {
      revert InvalidAddress();
    }

    aegisConfig = _config;
    emit SetAegisConfigAddress(address(_config));
  }

  function _setFeedRegistryAddress(FeedRegistryInterface _registry) internal {
    _feedRegistry = _registry;
    emit SetFeedRegistryAddress(address(_registry));
  }

  function _rejectRedeemRequest(string calldata requestId, RedeemRequest storage request) internal {
    request.status = RedeemRequestStatus.REJECTED;

    // Unlock YUSD
    totalRedeemLockedYUSD -= request.order.yusdAmount;
    yusd.safeTransfer(request.order.userWallet, request.order.yusdAmount);

    emit RejectRedeemRequest(requestId, _msgSender(), request.order.userWallet, request.order.yusdAmount);
  }

  function _custodyAvailableAssetBalance(address _asset) internal view returns (uint256) {
    uint256 custodyTransferrableFunds = _custodyTransferrableAssetFunds[_asset];
    uint256 balance = IERC20(_asset).balanceOf(address(this));
    if (balance < custodyTransferrableFunds || custodyTransferrableFunds < assetFrozenFunds[_asset]) {
      return 0;
    }

    return custodyTransferrableFunds - assetFrozenFunds[_asset];
  }

  function _untrackedAvailableAssetBalance(address _asset) internal view returns (uint256) {
    uint256 balance = IERC20(_asset).balanceOf(address(this));
    if (balance < _custodyTransferrableAssetFunds[_asset] + assetFrozenFunds[_asset]) {
      return 0;
    }

    return balance - _custodyTransferrableAssetFunds[_asset] - assetFrozenFunds[_asset];
  }

  function _calculateInsuranceFundFeeFromAmount(uint256 amount, uint16 feeBP) internal view returns (uint256, uint256) {
    if (insuranceFundAddress == address(0) || feeBP == 0) {
      return (amount, 0);
    }

    uint256 fee = (amount * feeBP) / MAX_BPS;

    return (amount - fee, fee);
  }

  function _calculateMinYUSDAmount(address collateralAsset, uint256 collateralAmount, uint256 yusdAmount) internal view returns (uint256) {
    (uint256 chainlinkPrice, uint8 feedDecimals) = _getAssetUSDPriceChainlink(collateralAsset);
    if (chainlinkPrice == 0) {
      return yusdAmount;
    }

    uint256 chainlinkYUSDAmount = Math.mulDiv(
      collateralAmount * 10 ** (18 - IERC20Metadata(collateralAsset).decimals()),
      chainlinkPrice,
      10 ** feedDecimals
    );

    // Return smallest amount
    return Math.min(yusdAmount, chainlinkYUSDAmount);
  }

  function _calculateRedeemMinCollateralAmount(
    address collateralAsset,
    uint256 collateralAmount,
    uint256 yusdAmount
  ) internal view returns (uint256) {
    // Calculate collateral amount for chainlink asset price.
    (uint256 chainlinkPrice, uint8 feedDecimals) = _getAssetUSDPriceChainlink(collateralAsset);
    if (chainlinkPrice > 0) {
      uint256 chainlinkCollateralAmount = Math.mulDiv(
        yusdAmount,
        10 ** feedDecimals,
        chainlinkPrice * 10 ** (18 - IERC20Metadata(collateralAsset).decimals())
      );

      // Get smallest amount
      collateralAmount = Math.min(collateralAmount, chainlinkCollateralAmount);
    }

    // Calculate collateral amount for aegisOracle asset/YUSD price.
    (uint256 oraclePrice, uint8 oracleDecimals) = _getAssetYUSDPriceOracle(collateralAsset);
    if (oraclePrice > 0) {
      uint256 oracleCollateralAmount = Math.mulDiv(
        yusdAmount,
        10 ** oracleDecimals,
        oraclePrice * 10 ** (18 - IERC20Metadata(collateralAsset).decimals())
      );

      // Get smallest amount
      collateralAmount = Math.min(collateralAmount, oracleCollateralAmount);
    }

    return collateralAmount;
  }

  function _checkMintRedeemLimit(MintRedeemLimit storage limits, uint256 yusdAmount) internal {
    if (limits.periodDuration == 0 || limits.maxPeriodAmount == 0) {
      return;
    }
    uint256 currentPeriodEndTime = limits.currentPeriodStartTime + limits.periodDuration;
    if (
      (currentPeriodEndTime >= block.timestamp && limits.currentPeriodTotalAmount + yusdAmount > limits.maxPeriodAmount) ||
      (currentPeriodEndTime < block.timestamp && yusdAmount > limits.maxPeriodAmount)
    ) {
      revert LimitReached();
    }
    // Start new mint period
    if (currentPeriodEndTime <= block.timestamp) {
      limits.currentPeriodStartTime = uint32(block.timestamp);
      limits.currentPeriodTotalAmount = 0;
    }

    limits.currentPeriodTotalAmount += yusdAmount;
  }

  function _getAssetUSDPriceChainlink(address asset) internal view returns (uint256, uint8) {
    if (address(_feedRegistry) == address(0)) {
      return (0, 0);
    }

    (, int256 answer, , uint256 updatedAt, ) = _feedRegistry.latestRoundData(asset, Denominations.USD);
    require(answer > 0, "Invalid price");
    require(updatedAt >= block.timestamp - chainlinkAssetHeartbeat[asset], "Stale price");

    return (uint256(answer), _feedRegistry.decimals(asset, Denominations.USD));
  }

  function _getAssetYUSDPriceOracle(address asset) internal view returns (uint256, uint8) {
    if (address(aegisOracle) == address(0)) {
      return (0, 0);
    }

    int256 yusdUSDPrice = aegisOracle.yusdUSDPrice();
    if (yusdUSDPrice == 0) {
      return (0, 0);
    }
    uint8 yusdUSDPriceDecimals = aegisOracle.decimals();
    (uint256 assetUSDPrice, ) = _getAssetUSDPriceChainlink(asset);

    return ((assetUSDPrice * 10 ** yusdUSDPriceDecimals) / uint256(yusdUSDPrice), yusdUSDPriceDecimals);
  }

  function _computeDomainSeparator() internal view returns (bytes32) {
    return keccak256(abi.encode(EIP712_DOMAIN, EIP712_NAME, EIP712_REVISION, block.chainid, address(this)));
  }
}
