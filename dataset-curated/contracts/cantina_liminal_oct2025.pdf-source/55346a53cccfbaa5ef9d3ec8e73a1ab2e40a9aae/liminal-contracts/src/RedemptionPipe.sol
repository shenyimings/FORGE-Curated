// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {INAVOracle} from "./interfaces/INAVOracle.sol";
import {IShareManager} from "./interfaces/IShareManager.sol";

interface IFeeManager {
    function accruePerformanceFee() external;
}

/**
 * @title RedemptionPipe
 * @notice Handles all redemptions (instant, fast, standard) for the vault
 * @dev Implements ERC7540-like interface with multiple redemption types
 * Does not strictly follow the ERC7540 spec as it has short-circuits and 
 * pushes the async request's assets on users instead of allowing for claim/pull.
 */
contract RedemptionPipe is
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;

    /// @notice Roles
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 public constant FULFILL_MANAGER_ROLE = keccak256("FULFILL_MANAGER_ROLE");
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");

    /// @notice Basis points constant (100% = 10000 basis points)
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Request ID (ERC7540 compatibility)
    uint256 internal constant REQUEST_ID = 0;

    /// @custom:storage-location erc7201:liminal.redemptionPipe.v1
    struct RedemptionPipeStorage {
        /// @notice Share manager contract
        IShareManager shareManager;
        /// @notice NAV oracle contract
        INAVOracle navOracle;
        /// @notice Underlying asset for redemptions
        IERC20Metadata underlyingAsset;
        /// @notice Liquidity provider for fulfillments
        address liquidityProvider;
        /// @notice Fee configuration
        FeeConfig fees;
        uint256 lastNAVForPerformance;
        /// @notice Recovery delay period (configurable) - uint24 safely fits 194 days in seconds
        uint24 recoveryDelay;
        /// @notice Last redemption timestamp for recovery check 
        uint72 lastRedemptionTime;
        /// @notice Treasury address for recovered assets
        address treasury;
        /// @notice Standard redemption mappings
        mapping(address => PendingRedeemRequest) pendingRedeem;
        /// @notice Fast redemption mappings
        mapping(address => PendingFastRedeemRequest) pendingFastRedeem;
        /// @notice Timelock controller for critical operations
        address timeLockController;
        /// @notice Minimum shares to prevent rounding to zero assets (OZ recommendation: 1000 units)
        /// Calculated as 1000 * 10^(18 - assetDecimals)
        uint256 MIN_AMOUNT_SHARES;
        /// @notice Fee manager for performance fee accrual
        IFeeManager feeManager;
        /// @notice Maximum custom fee in basis points for fast redeems
        uint256 maxCustomFeeBps;
        /// @notice Whether fast redemption is enabled
        bool fastRedeemEnabled;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.redemptionPipe.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REDEMPTION_PIPE_STORAGE_LOCATION =
        0x29501c6d0a5cf7bef3f2db502c4a21ddfa1dc6ae30f842b9bba4cfdd2f8c2a00;

    function _getRedemptionPipeStorage() private pure returns (RedemptionPipeStorage storage $) {
        assembly {
            $.slot := REDEMPTION_PIPE_STORAGE_LOCATION
        }
    }

    /// @notice Fee structure
    struct FeeConfig {
        uint256 instantRedeemFeeBps; // Basis points for instant redemption
        uint256 fastRedeemFeeBps; // Basis points for fast redemption
    }

    /// @notice Standard redemption request
    struct PendingRedeemRequest {
        uint256 shares;
        address receiver;
    }

    /// @notice Fast redemption request
    struct PendingFastRedeemRequest {
        uint256 shares;
        uint256 timestamp;
        address receiver;
    }

    /// Events
    event InstantRedeem(address indexed user, address indexed receiver, uint256 shares, uint256 assets, uint256 fee);
    event FastRedeemRequested(address indexed owner, address indexed receiver, uint256 shares, uint256 timestamp);
    event FastRedeemFulfilled(address indexed owner, address indexed receiver, uint256 assets, uint256 shares, uint256 fee);
    event RedeemRequested(address indexed owner, address indexed receiver, uint256 shares);
    event RedeemFulfilled(address indexed owner, address indexed receiver, uint256 assets, uint256 shares);
    event FeesUpdated(FeeConfig newFees);
    event RecoveryDelayUpdated(uint256 newDelay);
    event TreasuryUpdated(address indexed newTreasury);
    event AssetsRecovered(address indexed token, uint256 amount, address indexed treasury);
    event LiquidityProviderUpdated(address indexed oldProvider, address indexed newProvider);
    event MaxCustomFeeBpsUpdated(uint256 newMaxCustomFeeBps);
    event FastRedeemEnabledUpdated(bool enabled);
    event TimeLockControllerUpdated(address indexed oldTimeLockController, address indexed newTimeLockController);

    /// @notice Modifier for timelock-protected functions
    modifier onlyTimelock() {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        require(msg.sender == $.timeLockController, "RedemptionPipe: only timelock");
        _;
    }

    /// @notice Modifier to accrue performance fees before operations
    modifier accruePerformanceFee() {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.feeManager.accruePerformanceFee();
        _;
    }

    /// @notice Modifier to check if fast redemption is enabled
    modifier fastRedeemEnabledCheck() {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        require($.fastRedeemEnabled, "RedemptionPipe: fast redeem disabled");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Parameters for initialization
    struct InitializeParams {
        address shareManager;
        address navOracle;
        address underlyingAsset;
        address liquidityProvider;
        address deployer;
        address safeManager;
        address emergencyManager;
        address requestManager;
        address treasury;
        uint256 recoveryDelay;
        address timeLockController;
        address feeManager;
        uint256 maxCustomFeeBps;
    }

    /**
     * @notice Initialize the redemption pipe
     * @dev Ownership (DEFAULT_ADMIN_ROLE) is granted to deployer
     * @param params Struct containing all initialization parameters
     */
    function initialize(InitializeParams calldata params) external initializer {
        require(params.shareManager != address(0), "RedemptionPipe: zero share manager");
        require(params.navOracle != address(0), "RedemptionPipe: zero nav oracle");
        require(params.underlyingAsset != address(0), "RedemptionPipe: zero underlying");
        require(params.deployer != address(0), "RedemptionPipe: zero deployer");
        require(params.safeManager != address(0), "RedemptionPipe: zero safe manager");
        require(params.liquidityProvider != address(0), "RedemptionPipe: zero liquidity provider");
        require(params.emergencyManager != address(0), "RedemptionPipe: zero emergency manager");
        require(params.timeLockController != address(0), "RedemptionPipe: zero timelock");
        require(params.requestManager != address(0), "RedemptionPipe: zero request manager");
        require(params.treasury != address(0), "RedemptionPipe: zero treasury address");
        require(params.recoveryDelay > 0, "RedemptionPipe: zero delay");
        require(params.feeManager != address(0), "RedemptionPipe: zero fee manager");
        require(params.maxCustomFeeBps <= BASIS_POINTS, "RedemptionPipe: max custom fee exceeds 100%");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.shareManager = IShareManager(params.shareManager);
        $.navOracle = INAVOracle(params.navOracle);
        $.underlyingAsset = IERC20Metadata(params.underlyingAsset);
        $.liquidityProvider = params.liquidityProvider;
        $.treasury = params.treasury;
        $.recoveryDelay = uint24(params.recoveryDelay);
        $.timeLockController = params.timeLockController;
        $.feeManager = IFeeManager(params.feeManager);
        $.maxCustomFeeBps = params.maxCustomFeeBps;
        $.fastRedeemEnabled = false; // Default to disabled

        // Calculate minimum shares based on underlying asset decimals
        // MIN_AMOUNT = 1000 * 10^(18 - assetDecimals) to ensure at least 1000 units of assets
        uint8 assetDecimals = IERC20Metadata(params.underlyingAsset).decimals();
        require(assetDecimals <= 18, "RedemptionPipe: unsupported decimals");
        $.MIN_AMOUNT_SHARES = 1000 * 10 ** (18 - assetDecimals);

        // Grant ownership to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, params.deployer);
        _grantRole(SAFE_MANAGER_ROLE, params.safeManager);
        _grantRole(EMERGENCY_MANAGER_ROLE, params.emergencyManager);
        _grantRole(FULFILL_MANAGER_ROLE, params.requestManager);

        $.lastNAVForPerformance = $.navOracle.getNAV();
    }

    /**
     * @notice Recover stuck assets after recovery delay
     * @dev Can only be called when paused and after recovery delay since last redemption
     * @param token Address of token to recover
     * @param amount Amount to recover
     */
    function recoverAssets(address token, uint256 amount)
        external
        onlyRole(SAFE_MANAGER_ROLE)
        whenPaused
        nonReentrant
    {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        require($.treasury != address(0), "RedemptionPipe: treasury not set");
        require(block.timestamp > $.lastRedemptionTime + $.recoveryDelay, "RedemptionPipe: recovery delay not met");
        require(token != address(0), "RedemptionPipe: zero token address");
        require(amount > 0, "RedemptionPipe: zero amount");

        // Check balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "RedemptionPipe: insufficient balance");

        // Transfer to treasury
        IERC20(token).safeTransfer($.treasury, amount);

        emit AssetsRecovered(token, amount, $.treasury);
    }

    /**
     * @notice Update recovery delay
     * @param _recoveryDelay New recovery delay in seconds
     */
    function setRecoveryDelay(uint256 _recoveryDelay) external onlyTimelock {
        require(_recoveryDelay >= 7 days, "RedemptionPipe: delay too short");
        require(_recoveryDelay <= 90 days, "RedemptionPipe: delay too long");
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.recoveryDelay = uint24(_recoveryDelay);
        emit RecoveryDelayUpdated(_recoveryDelay);
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyTimelock {
        require(_treasury != address(0), "RedemptionPipe: zero address");
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @notice Get current fee configuration (returns individual values for backward compatibility)
    function fees() public view returns (uint256 _instantRedeemFeeBps, uint256 _fastRedeemFeeBps) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        return ($.fees.instantRedeemFeeBps, $.fees.fastRedeemFeeBps);
    }

    /// @notice Get individual fee components for backward compatibility
    function instantRedeemFeeBps() public view returns (uint256) {
        return _getRedemptionPipeStorage().fees.instantRedeemFeeBps;
    }

    function fastRedeemFeeBps() public view returns (uint256) {
        return _getRedemptionPipeStorage().fees.fastRedeemFeeBps;
    }

    /// @notice Get recovery delay
    function recoveryDelay() public view returns (uint256) {
        return _getRedemptionPipeStorage().recoveryDelay;
    }

    /// @notice Get treasury address
    function treasury() public view returns (address) {
        return _getRedemptionPipeStorage().treasury;
    }

    /// @notice Get liquidity provider address
    function liquidityProvider() public view returns (address) {
        return _getRedemptionPipeStorage().liquidityProvider;
    }

    /// @notice Get minimum amount required for redemption
    function MIN_AMOUNT_SHARES() public view returns (uint256) {
        return _getRedemptionPipeStorage().MIN_AMOUNT_SHARES;
    }

    /// @notice Get maximum custom fee in basis points
    function maxCustomFeeBps() public view returns (uint256) {
        return _getRedemptionPipeStorage().maxCustomFeeBps;
    }

    /// @notice Get fast redemption enabled status
    function fastRedeemEnabled() public view returns (bool) {
        return _getRedemptionPipeStorage().fastRedeemEnabled;
    }

    /// @notice Get timelock controller address
    function timeLockController() public view returns (address) {
        return _getRedemptionPipeStorage().timeLockController;
    }

    /**
     * @notice Update liquidity provider
     * @param _liquidityProvider New liquidity provider address
     */
    function setLiquidityProvider(address _liquidityProvider) external onlyTimelock {
        require(_liquidityProvider != address(0), "RedemptionPipe: zero address");
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        address oldProvider = $.liquidityProvider;
        $.liquidityProvider = _liquidityProvider;
        emit LiquidityProviderUpdated(oldProvider, _liquidityProvider);
    }

    /**
     * @notice Update maximum custom fee for fast redeems
     * @param _maxCustomFeeBps New maximum custom fee in basis points
     */
    function setMaxCustomFeeBps(uint256 _maxCustomFeeBps) external onlyTimelock {
        require(_maxCustomFeeBps <= BASIS_POINTS, "RedemptionPipe: max custom fee exceeds 100%");
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.maxCustomFeeBps = _maxCustomFeeBps;
        emit MaxCustomFeeBpsUpdated(_maxCustomFeeBps);
    }

    // ========== INSTANT REDEMPTION ==========

    /**
     * @notice Instant redemption using vault liquidity
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param controller Address that controls the shares
     * @return assets Amount of assets received
     */
    function redeem(uint256 shares, address receiver, address controller)
        external
        whenNotPaused
        nonReentrant
        accruePerformanceFee
        returns (uint256 assets)
    {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        require(
            controller == msg.sender || $.shareManager.isOperator(controller, msg.sender),
            "RedemptionPipe: unauthorized"
        );
        require(shares >= $.MIN_AMOUNT_SHARES, "RedemptionPipe: shares below minimum");
        require($.shareManager.balanceOf(controller) >= shares, "RedemptionPipe: insufficient shares");

        require(shares <= $.shareManager.maxWithdraw(), "RedemptionPipe: maximum redeem per user exceeded");


        // Calculate assets based on NAV
        assets = convertToAssets(shares);

        // Calculate fee in basis points (fee = assets * feeBps / BASIS_POINTS)
        uint256 fee = (assets * $.fees.instantRedeemFeeBps) / BASIS_POINTS;
        uint256 assetsAfterFee = assets - fee;


        // Update NAV. Fees stay with liquidityProvider, only decrease NAV by user's portion
        uint256 navDecrease = assetsAfterFee;
        $.navOracle.decreaseTotalAssets(navDecrease);

        // Burn shares
        $.shareManager.burnShares(controller, shares);

        uint256 lpBalance = $.underlyingAsset.balanceOf($.liquidityProvider);
        require(lpBalance >= assetsAfterFee, "RedemptionPipe: insufficient liquidity");

        // Transfer assets to user (fee stays with liquidity provider)
        $.underlyingAsset.safeTransferFrom($.liquidityProvider, receiver, assetsAfterFee);

        // Check if transfer was successful
        uint256 expectedLpBalance = lpBalance - assetsAfterFee; // Only user assets left LP
        require(
            $.underlyingAsset.balanceOf($.liquidityProvider) == expectedLpBalance,
            "RedemptionPipe: liquidity provider balance mismatch"
        );
        $.lastRedemptionTime = uint72(block.timestamp);

        emit InstantRedeem(controller, receiver, shares, assetsAfterFee, fee);

        return assetsAfterFee;
    }

    /**
     * @notice Instant withdrawal of specific asset amount
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param controller Address that controls the shares
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,  // NET amount user wants to receive
        address receiver,
        address controller
    ) external whenNotPaused nonReentrant accruePerformanceFee returns (uint256 shares) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        
        require(
            controller == msg.sender ||
                $.shareManager.isOperator(controller, msg.sender),
            "RedemptionPipe: unauthorized"
        );
        require(assets > 0, "RedemptionPipe: zero assets");
        
        
        // Calculate gross assets needed (same calculation as redeem() but in reverse)
        uint256 grossAssets = assets.mulDiv(
            BASIS_POINTS, 
            BASIS_POINTS - $.fees.instantRedeemFeeBps,
            Math.Rounding.Floor
        );
        
        // Calculate shares needed based on gross assets (before fee)
        shares = convertToShares(grossAssets);

        require(shares <= $.shareManager.maxWithdraw(), "RedemptionPipe: maximum redeem per user exceeded");
        require(shares >= $.MIN_AMOUNT_SHARES, "RedemptionPipe: shares below minimum");
        require(
            $.shareManager.balanceOf(controller) >= shares,
            "RedemptionPipe: insufficient shares"
        );
        
        // Calculate the actual assets and fee that this shares amount would produce
        uint256 actualAssets = convertToAssets(shares);
        uint256 fee = (actualAssets * $.fees.instantRedeemFeeBps) / BASIS_POINTS;
        uint256 actualNetAssets = actualAssets - fee;
        
        
        // Update NAV by user's net portion (fees stay with liquidity provider)
        $.navOracle.decreaseTotalAssets(actualNetAssets);
        
        // Burn shares
        $.shareManager.burnShares(controller, shares);
        
        // Transfer NET assets to user (what they requested)
        $.underlyingAsset.safeTransferFrom($.liquidityProvider, receiver, actualNetAssets);
        $.lastRedemptionTime = uint72(block.timestamp);
        
        emit InstantRedeem(controller, receiver, shares, actualNetAssets, fee);
        
        return shares;
    }

    // ========== FAST REDEMPTION ==========

    /**
     * @notice Request fast redemption
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets when fulfilled
     * @param controller Address that will control the redemption
     * @param owner Owner of the shares
     * @return requestId Always returns 0 (single request per owner)
     */
    function requestRedeemFast(uint256 shares, address receiver, address controller, address owner)
        external
        whenNotPaused
        fastRedeemEnabledCheck
        returns (uint256 requestId)
    {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        require(owner == msg.sender || $.shareManager.isOperator(owner, msg.sender), "RedemptionPipe: unauthorized");
        require(
            controller == msg.sender || $.shareManager.isOperator(controller, msg.sender),
            "RedemptionPipe: unauthorized controller"
        );
        require(receiver != address(0), "RedemptionPipe: zero receiver");
        require(shares >= $.MIN_AMOUNT_SHARES, "RedemptionPipe: shares below minimum");
        require($.shareManager.balanceOf(owner) >= shares, "RedemptionPipe: insufficient shares");

        // Check total pending shares (existing + new request) against maxWithdraw
        uint256 totalPendingAfter = _getTotalPendingShares(owner) + shares;
        require(totalPendingAfter <= $.shareManager.maxWithdraw(), "RedemptionPipe: maximum redeem per user exceeded");

        // Transfer shares to this contract for custody
        $.shareManager.transferFrom(owner, address(this), shares);

        uint256 currentPendingShares = $.pendingFastRedeem[owner].shares;
        $.pendingFastRedeem[owner] = PendingFastRedeemRequest(shares + currentPendingShares, block.timestamp, receiver);

        emit FastRedeemRequested(owner, receiver, shares, block.timestamp);
        return REQUEST_ID;
    }

    /**
     * @notice Fulfill fast redemption requests
     * @param owners Array of owners
     * @param shares Array of share amounts
     * @param customFees Array of custom _getRedemptionPipeStorage().fees (or use default)
     */
    function fulfillFastRedeems(address[] calldata owners, uint256[] calldata shares, uint256[] calldata customFees)
        external
        onlyRole(FULFILL_MANAGER_ROLE)
        fastRedeemEnabledCheck
        accruePerformanceFee
    {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        uint256 length = owners.length;
        require(length == shares.length, "RedemptionPipe: length mismatch");

        for (uint256 i = 0; i < length; i++) {
            if (shares[i] > 0) {
                // Calculate assets for fee calculation
                uint256 assets = convertToAssets(shares[i]);
                // Use custom fee basis points if provided, otherwise use default
                uint256 feeBps = customFees.length > i ? customFees[i] : $.fees.fastRedeemFeeBps;
                require(feeBps <= BASIS_POINTS, "RedemptionPipe: Incorrect Custom Fee");
                require(feeBps <= $.maxCustomFeeBps, "RedemptionPipe: Custom fee exceeds maximum");
                uint256 fee = (assets * feeBps) / BASIS_POINTS;
                _fulfillFastRedeem(owners[i], shares[i], fee);
            }
        }
        $.lastRedemptionTime = uint72(block.timestamp);
    }

    /**
     * @notice Internal fast redeem fulfillment
     */
    function _fulfillFastRedeem(address owner, uint256 shares, uint256 fee) internal {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        require(!$.shareManager.isBlacklisted(owner), "RedemptionPipe: owner is blacklisted");

        PendingFastRedeemRequest storage request = $.pendingFastRedeem[owner];
        require(request.shares >= shares, "RedemptionPipe: insufficient pending");

        // Performance fees are accrued via modifier

        // Calculate assets based on current NAV
        uint256 assets = convertToAssets(shares);

        uint256 assetsAfterFee = assets - fee;

        // Update NAV. Fees stay with liquidityProvider, only decrease NAV by user's portion
        uint256 navDecrease = assetsAfterFee;
        $.navOracle.decreaseTotalAssets(navDecrease);

        // Update pending
        request.shares -= shares;

        // Burn shares held in custody
        $.shareManager.burnSharesFromSelf(shares);

        // Transfer assets to receiver (fee stays with liquidity provider)
        $.underlyingAsset.safeTransferFrom($.liquidityProvider, request.receiver, assetsAfterFee);

        emit FastRedeemFulfilled(owner, request.receiver, assetsAfterFee, shares, fee);
    }

    // ========== STANDARD REDEMPTION ==========

    /**
     * @notice Request standard redemption
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets when fulfilled
     * @param controller Address that will control the redemption (for ERC7540 compatibility)
     * @param owner Owner of the shares
     * @return requestId Always returns 0
     */
    function requestRedeem(uint256 shares, address receiver, address controller, address owner)
        external
        whenNotPaused
        returns (uint256 requestId)
    {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        PendingRedeemRequest storage request = $.pendingRedeem[owner];

        require(owner != address(0), "RedemptionPipe: unauthorized");
        require(shares >= $.MIN_AMOUNT_SHARES, "RedemptionPipe: shares below minimum");
        require($.shareManager.balanceOf(msg.sender) >= shares, "RedemptionPipe: insufficient shares");

        // Check authorization: msg.sender must be owner or operator of owner
        require(
            msg.sender == owner || $.shareManager.isOperator(owner, msg.sender),
            "RedemptionPipe: unauthorized"
        );

        // Check controller authorization
        require(controller != address(0), "RedemptionPipe: unauthorized controller");
        require(
            controller == owner || $.shareManager.isOperator(owner, controller),
            "RedemptionPipe: unauthorized controller"
        );

        require(receiver != address(0), "RedemptionPipe: zero receiver");

        // Check maximum withdraw limit
        uint256 currentPendingShares = request.shares;
        uint256 totalPendingAfterRequest = currentPendingShares + shares + $.pendingFastRedeem[owner].shares;
        require(
            totalPendingAfterRequest <= $.shareManager.maxWithdraw(),
            "RedemptionPipe: maximum redeem per user exceeded"
        );

        // Transfer shares to this contract for custody
        $.shareManager.transferFrom(msg.sender, address(this), shares);

        // Add to pending
        request.shares = shares + currentPendingShares;
        request.receiver = receiver;

        emit RedeemRequested(owner, receiver, shares);
        return REQUEST_ID;
    }

    /**
     * @notice Fulfill standard redemption requests
     * @param owners Array of owners
     * @param shares Array of share amounts
     */
    function fulfillRedeems(address[] calldata owners, uint256[] calldata shares)
        external
        onlyRole(FULFILL_MANAGER_ROLE)
        accruePerformanceFee
    {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        uint256 length = owners.length;
        require(length == shares.length, "RedemptionPipe: length mismatch");

        for (uint256 i = 0; i < length; i++) {
            if (shares[i] > 0) {
                _fulfillRedeem(owners[i], shares[i]);
            }
        }
        $.lastRedemptionTime = uint72(block.timestamp);
    }

    /**
     * @notice Internal standard redeem fulfillment
     */
    function _fulfillRedeem(address owner, uint256 shares) internal {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        require(!$.shareManager.isBlacklisted(owner), "RedemptionPipe: owner is blacklisted");

        PendingRedeemRequest storage request = $.pendingRedeem[owner];
        require(request.shares >= shares, "RedemptionPipe: insufficient pending");

        // Performance fees are accrued via modifier

        // Calculate assets
        uint256 assets = convertToAssets(shares);

        // Update NAV - full amount leaves system (no fees)
        $.navOracle.decreaseTotalAssets(assets);

        // Update pending
        request.shares -= shares;

        // Burn shares
        $.shareManager.burnSharesFromSelf(shares);

        // Transfer full assets to receiver (no fees)
        $.underlyingAsset.safeTransferFrom($.liquidityProvider, request.receiver, assets);

        emit RedeemFulfilled(owner, request.receiver, assets, shares);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get total pending shares for a user (both standard and fast redemptions)
     * @param owner Owner address
     * @return Total pending shares
     */
    function _getTotalPendingShares(address owner) internal view returns (uint256) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        return $.pendingRedeem[owner].shares + $.pendingFastRedeem[owner].shares;
    }

    /**
     * @notice Preview redeem - converts shares to underlying assets after instant fees
     * @param shares Amount of shares to redeem
     * @return assets Expected underlying assets received (after instant fees)
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        require(shares > 0, "RedemptionPipe: zero shares");
        require(shares >= $.MIN_AMOUNT_SHARES, "RedemptionPipe: shares less than min amount");
        require(shares <= $.shareManager.maxWithdraw(), "RedemptionPipe: maximum redeem per user exceeded");

        // Convert shares to underlying assets (in native decimals)
        uint256 assets = convertToAssets(shares);
        
        // Calculate instant redemption fee in basis points
        uint256 fee = (assets * $.fees.instantRedeemFeeBps) / BASIS_POINTS;
        
        // Return assets after fee (what user actually receives from instant redemption)
        return assets - fee;
    }

    /**
     * @notice Preview withdraw - calculates required shares for net asset amount
     * @param assets Net asset amount (what user wants to receive after fees)
     * @return shares Required shares to burn
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        require(assets > 0, "RedemptionPipe: zero assets");

        // Calculate gross assets needed (same calculation as withdraw() but in reverse)
        uint256 grossAssets = assets.mulDiv(
            BASIS_POINTS, 
            BASIS_POINTS - $.fees.instantRedeemFeeBps,
            Math.Rounding.Floor
        );
        
        uint256 shares = convertToShares(grossAssets);

        require(shares <= $.shareManager.maxWithdraw(), "RedemptionPipe: maximum redeem per user exceeded");
        require(shares >= $.MIN_AMOUNT_SHARES, "RedemptionPipe: shares less than min amount");
        return shares;
    }

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return assets Equivalent asset amount
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        uint256 totalSupply = $.shareManager.totalSupply();
        uint256 totalAssets = $.navOracle.getNAV();

        uint8 underlyingDecimals = $.underlyingAsset.decimals();
        uint256 decimalsDiff = 18 - underlyingDecimals;
        uint256 scaleFactor = 10 ** decimalsDiff;

        if (totalSupply == 0) {
            // When no supply, convert decimals directly
            return shares / scaleFactor;
        }

        // Calculate value in 18 decimals
        uint256 value18 = shares.mulDiv(totalAssets, totalSupply, Math.Rounding.Floor);

        // Convert from 18 decimals to underlying asset decimals
        return value18 / scaleFactor;
    }

    /**
     * @notice Convert assets to shares
     * @param assets Amount of assets
     * @return shares Equivalent share amount
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (assets == 0) {
            return 0;
        }
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        uint256 totalSupply = $.shareManager.totalSupply();
        uint256 totalAssets = $.navOracle.getNAV();

        uint8 underlyingDecimals = $.underlyingAsset.decimals();
        uint256 decimalsDiff = 18 - underlyingDecimals;
        uint256 scaleFactor = 10 ** decimalsDiff;

        if (totalSupply == 0) {
            // When no supply, convert decimals directly
            return assets * scaleFactor;
        }

        // Convert from underlying asset decimals to 18 decimals
        uint256 value18 = assets * scaleFactor;

        // Calculate shares
        return value18.mulDiv(totalSupply, totalAssets, Math.Rounding.Ceil);
    }

    /**
     * @notice Get pending fast redeem request
     * @param owner Owner address
     * @return shares Amount of pending shares
     * @return timestamp Request timestamp
     * @return receiver Address that will receive the assets
     */
    function pendingFastRedeemRequest(address owner) external view returns (uint256 shares, uint256 timestamp, address receiver) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        PendingFastRedeemRequest memory request = $.pendingFastRedeem[owner];
        return (request.shares, request.timestamp, request.receiver);
    }

    /**
     * @notice Get pending standard redeem request
     * @param owner Owner address
     * @return shares Amount of pending shares
     * @return receiver Address that will receive the assets
     */
    function pendingRedeemRequest(address owner) external view returns (uint256 shares, address receiver) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        PendingRedeemRequest memory request = $.pendingRedeem[owner];
        return (request.shares, request.receiver);
    }

    /**
     * @notice Maximum amount of shares that can be redeemed from the owner balance through a redeem call
     * @param owner Address of the owner
     * @return Maximum amount of shares that can be redeemed
     * @dev ERC4626 compliant - considers balance, pending requests, and maxWithdraw limit
     */
    function maxRedeem(address owner) external view returns (uint256) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        // Get owner's balance
        uint256 balance = $.shareManager.balanceOf(owner);
        if (balance == 0) {
            return 0;
        }

        // Get total pending shares (both standard and fast redemptions)
        uint256 totalPending = _getTotalPendingShares(owner);

        // Get maximum shares allowed by ShareManager policy
        uint256 maxWithdrawShares = $.shareManager.maxWithdraw();

        // Calculate remaining capacity for new redemptions
        uint256 remainingCapacity = maxWithdrawShares > totalPending ? maxWithdrawShares - totalPending : 0;

        // Return the minimum of owner's balance and remaining capacity
        uint256 maxShares = balance < remainingCapacity ? balance : remainingCapacity;

        // Ensure it meets minimum requirement, otherwise return 0
        if (maxShares < $.MIN_AMOUNT_SHARES) {
            return 0;
        }

        return maxShares;
    }

    /**
     * @notice Maximum amount of underlying assets that can be withdrawn from the owner balance through a withdraw call
     * @param owner Address of the owner
     * @return Maximum amount of assets that can be withdrawn
     * @dev ERC4626 compliant - converts maxRedeem to assets after accounting for instant redemption fees
     */
    function maxWithdraw(address owner) external view returns (uint256) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();

        // Return 0 if contract is paused
        if (paused()) {
            return 0;
        }

        // Get owner's balance
        uint256 balance = $.shareManager.balanceOf(owner);
        if (balance == 0) {
            return 0;
        }

        // Get total pending shares (both standard and fast redemptions)
        uint256 totalPending = _getTotalPendingShares(owner);

        // Get maximum shares allowed by ShareManager policy
        uint256 maxWithdrawShares = $.shareManager.maxWithdraw();

        // Calculate remaining capacity for new redemptions
        uint256 remainingCapacity = maxWithdrawShares > totalPending ? maxWithdrawShares - totalPending : 0;

        // Return the minimum of owner's balance and remaining capacity
        uint256 maxAllowedShares = balance < remainingCapacity ? balance : remainingCapacity;

        // Ensure it meets minimum requirement, otherwise return 0
        if (maxAllowedShares < $.MIN_AMOUNT_SHARES) {
            return 0;
        }

        // Convert to assets and apply instant redemption fee
        uint256 assets = convertToAssets(maxAllowedShares);
        uint256 fee = (assets * $.fees.instantRedeemFeeBps) / BASIS_POINTS;

        return assets - fee;
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Update timelock controller address
     * @param _timelockController New timelock controller address
     */
    function setTimelockController(address _timelockController) external onlyTimelock {
        require(_timelockController != address(0), "RedemptionPipe: zero timelock");
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        address oldTimeLockController = $.timeLockController;
        $.timeLockController = _timelockController;
        emit TimeLockControllerUpdated(oldTimeLockController, _timelockController);
    }

    /**
     * @notice Update fee configuration
     * @param _fees New fee configuration
     */
    function setFees(FeeConfig calldata _fees) external onlyTimelock {
        require(_fees.instantRedeemFeeBps <= BASIS_POINTS, "RedemptionPipe: instant fee exceeds 100%");
        require(_fees.fastRedeemFeeBps <= BASIS_POINTS, "RedemptionPipe: fast fee exceeds 100%");
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.fees = _fees;
        emit FeesUpdated(_fees);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Update fast redemption enabled status
     * @param _enabled New fast redemption enabled status
     */
    function setFastRedeemEnabled(bool _enabled) external onlyRole(SAFE_MANAGER_ROLE) {
        RedemptionPipeStorage storage $ = _getRedemptionPipeStorage();
        $.fastRedeemEnabled = _enabled;
        emit FastRedeemEnabledUpdated(_enabled);
    }
}
