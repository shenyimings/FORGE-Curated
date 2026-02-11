// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {INAVOracle} from "./interfaces/INAVOracle.sol";
import {IShareManager} from "./interfaces/IShareManager.sol";

interface IFeeManager {
    function accruePerformanceFee() external;
}

/**
 * @title DepositPipe
 * @notice Handles deposits for a specific asset
 * @dev Implements IERC4626 interface for compatibility, delegates share management to ShareManager
 * @dev Inherits ERC20Upgradeable only for IERC4626 compatibility (name, symbol, decimals)
 *      The actual share balances and transfers are NOT managed by this contract but by ShareManager
 */
contract DepositPipe is
    ERC20Upgradeable,
    IERC4626,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Role for emergency pause/unpause operations
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    /// @notice Role for keeper operations
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @custom:storage-location erc7201:liminal.depositPipe.v1
    struct DepositPipeStorage {
        /// @notice Share manager contract
        IShareManager shareManager;
        /// @notice Price oracle for conversions
        IPriceOracle priceOracle;
        /// @notice NAV oracle for total value tracking
        INAVOracle navOracle;
        /// @notice Deposit asset (the asset accepted for deposits)
        address depositAsset;
        /// @notice Underlying asset of the vault (redemption asset)
        address underlyingAsset;
        /// @notice Strategist address to receive deposits
        address strategist;
        /// @notice Keeper address for depositFor operations
        address keeper;
        /// @notice Timelock controller for critical operations
        address timeLockController;
        /// @notice Minimum shares to prevent rounding to zero assets (OZ recommendation: 1000 units)
        /// Calculated as 1000 * 10^(18 - assetDecimals)
        uint256 MIN_AMOUNT_SHARES;
        /// @notice Optional fee manager to crystallize performance fee before deposits
        address feeManager;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.depositPipe.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DEPOSIT_PIPE_STORAGE_LOCATION =
        0x8181ed37ae785402ef857f5d1a6b18f3cfc3c3050c29b53fffd1ba0acd9e0600;

    function _getDepositPipeStorage() private pure returns (DepositPipeStorage storage $) {
        assembly {
            $.slot := DEPOSIT_PIPE_STORAGE_LOCATION
        }
    }

    /// Events
    event DepositProcessed(
        address indexed depositor, address indexed receiver, uint256 assetsIn, uint256 sharesOut
    );
    event StrategistUpdated(address indexed oldStrategist, address indexed newStrategist);

    event TimeLockControllerUpdated(address indexed oldTimeLockController, address indexed newTimeLockController);

    /// @notice Modifier for timelock-protected functions
    modifier onlyTimelock() {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        require(msg.sender == $.timeLockController, "DepositPipe: only timelock");
        _;
    }

    /// @notice Modifier to accrue performance fees before operations
    modifier accruePerformanceFee() {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        if ($.feeManager != address(0)) {
            IFeeManager($.feeManager).accruePerformanceFee();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Parameters for initialization
    struct InitializeParams {
        address depositAsset;
        string name;
        string symbol;
        address shareManager;
        address priceOracle;
        address navOracle;
        address underlyingAsset;
        address strategist;
        address deployer;
        address emergencyManager;
        address keeper;
        address timeLockController;
        address feeManager;
    }

    /**
     * @notice Initialize the deposit pipe
     * @dev Ownership (DEFAULT_ADMIN_ROLE) is granted to deployer
     * @param params Struct containing all initialization parameters
     */
    function initialize(InitializeParams calldata params) external initializer {
        require(params.depositAsset != address(0), "DepositPipe: zero asset");
        require(params.shareManager != address(0), "DepositPipe: zero share manager");
        require(params.priceOracle != address(0), "DepositPipe: zero oracle");
        require(params.navOracle != address(0), "DepositPipe: zero nav oracle");
        require(params.underlyingAsset != address(0), "DepositPipe: zero underlying");
        require(params.strategist != address(0), "DepositPipe: zero strategist");
        require(params.deployer != address(0), "DepositPipe: zero deployer");
        require(params.keeper != address(0), "DepositPipe: zero keeper");
        require(params.timeLockController != address(0), "DepositPipe: zero timelock");
        require(params.feeManager != address(0), "DepositPipe: zero fee manager");

        __ERC20_init(params.name, params.symbol);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        DepositPipeStorage storage $ = _getDepositPipeStorage();
        $.shareManager = IShareManager(params.shareManager);
        $.priceOracle = IPriceOracle(params.priceOracle);
        $.navOracle = INAVOracle(params.navOracle);
        $.depositAsset = params.depositAsset;
        $.underlyingAsset = params.underlyingAsset;
        $.strategist = params.strategist;
        $.keeper = params.keeper;
        $.timeLockController = params.timeLockController;
        $.feeManager = params.feeManager;
        // Calculate minimum shares based on underlying asset decimals
        // MIN_AMOUNT_SHARES = 1000 * 10^(18 - assetDecimals) to ensure at least 1000 units of assets
        uint8 underlyingDecimals = IERC20Metadata(params.underlyingAsset).decimals();
        require(underlyingDecimals <= 18, "DepositPipe: unsupported underlying decimals");
        $.MIN_AMOUNT_SHARES = 1000 * 10**(18 - underlyingDecimals);

        // Grant ownership to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, params.deployer);
        _grantRole(EMERGENCY_MANAGER_ROLE, params.emergencyManager);
        _grantRole(KEEPER_ROLE, params.keeper);
    }


    /**
     * @notice Deposit assets and receive shares (ERC4626 standard)
     * @param assets Amount of deposit asset
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        return deposit(assets, receiver, msg.sender, 0);
    }

    /**
     * @notice Deposit assets with controller
     * @param assets Amount of deposit asset
     * @param receiver Address to receive shares
     * @param controller Address that owns the assets
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver, address controller) public returns (uint256 shares) {
        return deposit(assets, receiver, controller, 0);
    }

    /**
     * @notice Deposit assets with slippage protection
     * @param assets Amount of deposit asset
     * @param receiver Address to receive shares
     * @param minShares Minimum shares to receive (slippage protection)
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver, uint256 minShares) public returns (uint256 shares) {
        return deposit(assets, receiver, msg.sender, minShares);
    }

    /**
     * @notice Deposit with controller and slippage protection
     * @param assets Amount of deposit asset
     * @param receiver Address to receive shares
     * @param controller Address that owns the assets
     * @param minShares Minimum shares to receive (slippage protection)
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver, address controller, uint256 minShares)
        public
        whenNotPaused
        nonReentrant
        accruePerformanceFee
        returns (uint256 shares)
    {
        DepositPipeStorage storage $ = _getDepositPipeStorage();

        // Check authorization
        require(
            controller == msg.sender || $.shareManager.isOperator(controller, msg.sender), "DepositPipe: unauthorized"
        );

        require(assets > 0, "DepositPipe: zero assets");

        // Transfer assets from controller
        IERC20($.depositAsset).safeTransferFrom(controller, address(this), assets);

        // Convert to underlying asset value (oracle returns native decimals)
        uint256 underlyingValue = $.priceOracle.convertAmount($.depositAsset, $.underlyingAsset, assets);
        uint256 underlyingValue18 = _normalizeToDecimals18(underlyingValue);

        // Calculate shares based on NAV (now both in 18 decimals)
        shares = _convertToShares(underlyingValue18);
        require(shares >= $.MIN_AMOUNT_SHARES, "DepositPipe: shares below minimum");
        require(shares >= minShares, "DepositPipe: slippage exceeded");

        // Check max deposit per user before minting
        require($.shareManager.balanceOf(receiver) + shares <= $.shareManager.maxDeposit(), "ShareManager: max deposit exceeded");
        require($.shareManager.totalSupply() + shares <= $.shareManager.maxSupply(), "DepositPipe: max supply exceeded");

        // Transfer assets to strategist
        IERC20($.depositAsset).safeTransfer($.strategist, assets);

        // Update NAV oracle
        $.navOracle.increaseTotalAssets(underlyingValue);

        // Mint shares via ShareManager
        $.shareManager.mintShares(receiver, shares);

        emit DepositProcessed(controller, receiver, assets, shares);
        emit Deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    /**
     * @notice Mint specific amount of shares (ERC4626 standard)
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets required
     */
    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        return mint(shares, receiver, msg.sender);
    }

    /**
     * @notice Mint shares with controller
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @param controller Address that owns the assets
     * @return assets Amount of assets required
     */
    function mint(uint256 shares, address receiver, address controller) public returns (uint256 assets) {
        return mint(shares, receiver, controller, type(uint256).max);
    }

    /**
     * @notice Mint shares with slippage protection
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @param maxAssets Maximum assets to spend (slippage protection)
     * @return assets Amount of assets required
     */
    function mint(uint256 shares, address receiver, uint256 maxAssets) public returns (uint256 assets) {
        return mint(shares, receiver, msg.sender, maxAssets);
    }

    /**
     * @notice Mint with controller and slippage protection
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @param controller Address that owns the assets
     * @param maxAssets Maximum assets to spend (slippage protection)
     * @return assets Amount of assets required
     */
    function mint(uint256 shares, address receiver, address controller, uint256 maxAssets)
        public
        whenNotPaused
        nonReentrant
        accruePerformanceFee
        returns (uint256 assets)
    {
        DepositPipeStorage storage $ = _getDepositPipeStorage();

        // Check authorization
        require(
            controller == msg.sender || $.shareManager.isOperator(controller, msg.sender), "DepositPipe: unauthorized"
        );

        require(shares >= $.MIN_AMOUNT_SHARES, "DepositPipe: shares below minimum");
        require($.shareManager.balanceOf(receiver) + shares <= $.shareManager.maxDeposit(), "ShareManager: max deposit exceeded");
        require($.shareManager.totalSupply() + shares <= $.shareManager.maxSupply(), "DepositPipe: max supply exceeded");

        // Calculate required underlying value for shares (returns 18 decimals)
        uint256 underlyingValue18 = _convertToAssets(shares);

        // Convert from 18 decimals to underlying asset's native decimals
        uint256 underlyingValueNative = _normalizeFromDecimals18(underlyingValue18);

        // Convert from underlying to deposit asset (using native decimals)
        assets = $.priceOracle.convertAmount($.underlyingAsset, $.depositAsset, underlyingValueNative);

        // Check slippage protection
        require(assets <= maxAssets, "DepositPipe: slippage exceeded");

        // Transfer assets from controller
        IERC20($.depositAsset).safeTransferFrom(controller, address(this), assets);

        // Transfer assets to strategist
        IERC20($.depositAsset).safeTransfer($.strategist, assets);

        // Update NAV oracle
        $.navOracle.increaseTotalAssets(underlyingValueNative);

        // Mint shares via ShareManager
        $.shareManager.mintShares(receiver, shares);

        emit DepositProcessed(controller, receiver, assets, shares);
        emit Deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    /**
     * @notice Convert underlying value to shares
     * @param underlyingValue Value in underlying asset
     * @return shares Amount of shares
     */
    function _convertToShares(uint256 underlyingValue) internal view returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint256 sharesTotalSupply = $.shareManager.totalSupply();
        uint256 totalAssets_ = $.navOracle.getNAV();

        if (sharesTotalSupply == 0) {
            // For first deposit, underlyingValue is already in 18 decimals (underlying asset decimals)
            // Shares should also be in 18 decimals, so return 1:1
            return underlyingValue;
        }

        // Both underlyingValue and totalAssets_ are in 18 decimals (underlying asset decimals)
        // totalSupply is in 18 decimals (shares decimals)
        // To maintain the ratio: shares/totalSupply = value/totalAssets
        // We need: shares = (value * totalSupply) / totalAssets
        // Since the result should be in 18 decimals like totalSupply, this works correctly
        return underlyingValue.mulDiv(sharesTotalSupply, totalAssets_, Math.Rounding.Floor);
    }

    /**
     * @notice Convert shares to underlying value
     * @param shares Amount of shares
     * @return underlyingValue Value in underlying asset
     */
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint256 sharesTotalSupply = $.shareManager.totalSupply();
        uint256 totalAssets_ = $.navOracle.getNAV();

        if (sharesTotalSupply == 0) {
            // When no shares exist, 1 share = 1 underlying token (both 18 decimals)
            return shares;
        }

        // value = shares * totalAssets / totalSupply
        return shares.mulDiv(totalAssets_, sharesTotalSupply, Math.Rounding.Ceil);
    }

    // ========== INTERNAL HELPERS ==========

    /**
     * @notice Normalize value to 18 decimals from underlying asset's decimals
     * @param valueNative Value in underlying asset's native decimals
     * @return value18 Value normalized to 18 decimals
     */
    function _normalizeToDecimals18(uint256 valueNative) internal view returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint8 underlyingDecimals = IERC20Metadata($.underlyingAsset).decimals();

        if (underlyingDecimals == 18) {
            return valueNative;
        } else {
            // This is safe because underlyingDecimals is always 18 or less
            uint256 scaleFactor = 10 ** (18 - underlyingDecimals);
            return valueNative * scaleFactor;
        }
    }

    /**
     * @notice Convert value from 18 decimals to underlying asset's decimals
     * @param value18 Value in 18 decimals
     * @return valueNative Value in underlying asset's native decimals
     */
    function _normalizeFromDecimals18(uint256 value18) internal view returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint8 underlyingDecimals = IERC20Metadata($.underlyingAsset).decimals();

        if (underlyingDecimals == 18) {
            return value18;
        } else {
            // This is safe because underlyingDecimals is always 18 or less
            uint256 scaleFactor = 10 ** (18 - underlyingDecimals);
            return value18 / scaleFactor;
        }
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get the deposit asset address
     * @return Address of the deposit asset
     */
    function asset() public view virtual override returns (address) {
        return _getDepositPipeStorage().depositAsset;
    }

    /**
     * @notice Override totalSupply to return 0 (shares managed by ShareManager)
     */
    function totalSupply() public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @notice Override balanceOf to return 0 (shares managed by ShareManager)
     */
    function balanceOf(address) public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @notice Override transfer to revert (shares managed by ShareManager)
     */
    function transfer(address, uint256) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        revert("DepositPipe: transfers not supported");
    }

    /**
     * @notice Override allowance to return 0 (shares managed by ShareManager)
     */
    function allowance(address, address) public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @notice Override approve to revert (shares managed by ShareManager)
     */
    function approve(address, uint256) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        revert("DepositPipe: approvals not supported");
    }

    /**
     * @notice Override transferFrom to revert (shares managed by ShareManager)
     */
    function transferFrom(address, address, uint256) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        revert("DepositPipe: transfers not supported");
    }

    /**
     * @notice Preview deposit - converts assets to shares
     * @param assets Amount of deposit asset
     * @return shares Expected shares
     */
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        require(assets > 0, "DepositPipe: zero assets");

        uint256 underlyingValueNative = $.priceOracle.convertAmount($.depositAsset, $.underlyingAsset, assets);

        // Normalize to 18 decimals
        uint256 underlyingValue18 = _normalizeToDecimals18(underlyingValueNative);

        uint256 shares = _convertToShares(underlyingValue18);
        require(shares >= $.MIN_AMOUNT_SHARES, "DepositPipe: shares below minimum");
        require($.shareManager.balanceOf(msg.sender) + shares <= $.shareManager.maxDeposit(), "ShareManager: max deposit exceeded");
        require($.shareManager.totalSupply() + shares <= $.shareManager.maxSupply(), "DepositPipe: max supply exceeded");

        return shares;
    }

    /**
     * @notice Preview mint - calculates required assets
     * @param shares Desired shares
     * @return assets Required deposit assets
     */
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        require(shares >= $.MIN_AMOUNT_SHARES, "DepositPipe: shares below minimum");
        require($.shareManager.balanceOf(msg.sender) + shares <= $.shareManager.maxDeposit(), "ShareManager: max deposit exceeded");
        require($.shareManager.totalSupply() + shares <= $.shareManager.maxSupply(), "DepositPipe: max supply exceeded");

        uint256 underlyingValue18 = _convertToAssets(shares);

        // Convert from 18 decimals to underlying asset's native decimals
        uint256 underlyingValueNative = _normalizeFromDecimals18(underlyingValue18);

        uint256 assets = $.priceOracle.convertAmount($.underlyingAsset, $.depositAsset, underlyingValueNative);
        return assets;
    }

    /**
     * @notice Preview deposit for a specific user - converts assets to shares
     * @param assets Amount of deposit asset
     * @param user Address of the user to check limits for
     * @return shares Expected shares
     */
    function previewDeposit(uint256 assets, address user) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        require(assets > 0, "DepositPipe: zero assets");

        uint256 underlyingValueNative = $.priceOracle.convertAmount($.depositAsset, $.underlyingAsset, assets);

        // Normalize to 18 decimals
        uint256 underlyingValue18 = _normalizeToDecimals18(underlyingValueNative);

        uint256 shares = _convertToShares(underlyingValue18);
        require(shares >= $.MIN_AMOUNT_SHARES, "DepositPipe: shares below minimum");
        require($.shareManager.balanceOf(user) + shares <= $.shareManager.maxDeposit(), "ShareManager: max deposit exceeded");
        require($.shareManager.totalSupply() + shares <= $.shareManager.maxSupply(), "DepositPipe: max supply exceeded");

        return shares;
    }

    /**
     * @notice Preview mint for a specific user - calculates required assets
     * @param shares Desired shares
     * @param user Address of the user to check limits for
     * @return assets Required deposit assets
     */
    function previewMint(uint256 shares, address user) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        require(shares >= $.MIN_AMOUNT_SHARES, "DepositPipe: shares below minimum");
        require($.shareManager.balanceOf(user) + shares <= $.shareManager.maxDeposit(), "ShareManager: max deposit exceeded");
        require($.shareManager.totalSupply() + shares <= $.shareManager.maxSupply(), "DepositPipe: max supply exceeded");

        uint256 underlyingValue18 = _convertToAssets(shares);

        // Convert from 18 decimals to underlying asset's native decimals
        uint256 underlyingValueNative = _normalizeFromDecimals18(underlyingValue18);

        uint256 assets = $.priceOracle.convertAmount($.underlyingAsset, $.depositAsset, underlyingValueNative);
        return assets;
    }

    /**
     * @notice Convert deposit assets to shares
     * @param assets Amount of deposit asset
     * @return shares Equivalent shares
     */
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint256 underlyingValueNative = $.priceOracle.convertAmount($.depositAsset, $.underlyingAsset, assets);
        uint256 underlyingValue18 = _normalizeToDecimals18(underlyingValueNative);
        return _convertToShares(underlyingValue18);
    }

    /**
     * @notice Convert shares to deposit assets
     * @param shares Amount of shares
     * @return assets Equivalent deposit assets
     */
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint256 underlyingValue18 = _convertToAssets(shares);
        uint256 underlyingValueNative = _normalizeFromDecimals18(underlyingValue18);
        return $.priceOracle.convertAmount($.underlyingAsset, $.depositAsset, underlyingValueNative);
    }

    /**
     * @notice Total assets managed by this pipe (always 0 as assets are forwarded)
     */
    function totalAssets() public view virtual returns (uint256) {
        return 0; // Assets are forwarded to strategist
    }

    /**
     * @notice Maximum deposit amount for a user
     * @param user User address
     * @return Maximum deposit amount in deposit asset
     */
    function maxDeposit(address user) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint256 currentUserShares = $.shareManager.balanceOf(user);
        uint256 maxDepositUserShares = $.shareManager.maxDeposit();
        uint256 currentTotalSupply = $.shareManager.totalSupply();
        uint256 maxSupply = $.shareManager.maxSupply();
        
        // Calculate remaining shares based on user limit
        uint256 remainingUserShares = 0;
        if (currentUserShares < maxDepositUserShares) {
            remainingUserShares = maxDepositUserShares - currentUserShares;
        }
        
        // Calculate remaining shares based on global supply limit
        uint256 remainingSupplyShares = 0;
        if (currentTotalSupply < maxSupply) {
            remainingSupplyShares = maxSupply - currentTotalSupply;
        }
        
        // Take the minimum of both limits
        uint256 maxShares = remainingUserShares < remainingSupplyShares ? remainingUserShares : remainingSupplyShares;
        
        if (maxShares < $.MIN_AMOUNT_SHARES) {
            return 0;
        }
        
        return convertToAssets(maxShares);
    }

    /**
     * @notice Maximum mint amount for a user
     * @param user User address
     * @return Maximum shares that can be minted
     */
    function maxMint(address user) public view virtual returns (uint256) {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        uint256 currentUserShares = $.shareManager.balanceOf(user);
        uint256 maxDepositUserShares = $.shareManager.maxDeposit();
        uint256 currentTotalSupply = $.shareManager.totalSupply();
        uint256 maxSupply = $.shareManager.maxSupply();
        
        // Calculate remaining shares based on user limit
        uint256 remainingUserShares = 0;
        if (currentUserShares < maxDepositUserShares) {
            remainingUserShares = maxDepositUserShares - currentUserShares;
        }
        
        // Calculate remaining shares based on global supply limit
        uint256 remainingSupplyShares = 0;
        if (currentTotalSupply < maxSupply) {
            remainingSupplyShares = maxSupply - currentTotalSupply;
        }
        
        // Take the minimum of both limits
        uint256 maxShares = remainingUserShares < remainingSupplyShares ? remainingUserShares : remainingSupplyShares;
        if (maxShares < $.MIN_AMOUNT_SHARES) {
            return 0;
        }

        return maxShares;
    }

    // Note: Redemption functions revert as this is deposit-only

    function maxWithdraw(address) public pure virtual returns (uint256) {
        return 0; // No withdrawals through deposit pipe
    }

    function maxRedeem(address) public pure virtual returns (uint256) {
        return 0; // No redemptions through deposit pipe
    }

    function previewWithdraw(uint256) public pure virtual returns (uint256) {
        revert("DepositPipe: withdraw not supported");
    }

    function previewRedeem(uint256) public pure virtual returns (uint256) {
        revert("DepositPipe: redeem not supported");
    }

    function withdraw(uint256, address, address) public pure virtual returns (uint256) {
        revert("DepositPipe: withdraw not supported");
    }

    function redeem(uint256, address, address) public pure virtual returns (uint256) {
        revert("DepositPipe: redeem not supported");
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Update deposit asset address
     * @param _timelockController New timelock controller address
     */
    function setTimelockController(address _timelockController) external onlyTimelock {
        require(_timelockController != address(0), "DepositPipe: zero timelock");
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        address oldTimeLockController = $.timeLockController;
        $.timeLockController = _timelockController;
        emit TimeLockControllerUpdated(oldTimeLockController, _timelockController);
    }

    /**
     * @notice Update strategist address
     * @param _strategist New strategist address
     */
    function setStrategist(address _strategist) external onlyTimelock {
        require(_strategist != address(0), "DepositPipe: zero address");
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        address oldStrategist = $.strategist;
        $.strategist = _strategist;
        emit StrategistUpdated(oldStrategist, _strategist);
    }

    /**
     * @notice Set FeeManager hook for crystallizing performance fees pre-deposit
     * @param _feeManager Address of the fee manager (set 0 to disable)
     */
    function setFeeManager(address _feeManager) external onlyTimelock {
        DepositPipeStorage storage $ = _getDepositPipeStorage();
        $.feeManager = _feeManager;
    }

    /// @notice Get configured FeeManager address
    function feeManager() public view returns (address) {
        return _getDepositPipeStorage().feeManager;
    }

    /// @notice Get strategist address
    function strategist() public view returns (address) {
        return _getDepositPipeStorage().strategist;
    }

    /// @notice Get timelock controller address
    function timeLockController() public view returns (address) {
        return _getDepositPipeStorage().timeLockController;
    }

    /// @notice Get minimum amount required for shares
    function MIN_AMOUNT_SHARES() public view returns (uint256) {
        return _getDepositPipeStorage().MIN_AMOUNT_SHARES;
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
     * @notice Recover tokens from the contract (timelock-protected)
     * @param token Token address to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyTimelock {
        require(token != address(0), "DepositPipe: zero token");
        require(to != address(0), "DepositPipe: zero recipient");
        require(amount > 0, "DepositPipe: zero amount");
        IERC20(token).safeTransfer(to, amount);
    }
}
