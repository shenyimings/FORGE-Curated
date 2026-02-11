// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {INAVOracle} from "./interfaces/INAVOracle.sol";
import {IShareManager} from "./interfaces/IShareManager.sol";

/**
 * @title FeeManager
 * @notice Centralized fee management for the vault system
 * @dev FEE_COLLECTOR_ROLE must be granted to the fee manager address
 * @dev Handles performance fees and management fees across all pipes
 */
contract FeeManager is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using Math for uint256;

    /// @notice Role for timelock operations
    bytes32 public constant SAFE_MANAGER_ROLE = keccak256("SAFE_MANAGER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    /// @notice Fee configuration
    struct FeeConfig {
        uint256 managementFeeBps; // Annual management fee in basis points
        uint256 performanceFeeBps; // Performance fee in basis points
    }

    /// @custom:storage-location erc7201:liminal.feeManager.v1
    struct FeeManagerStorage {
        /// @notice Core contracts
        IShareManager shareManager;
        INAVOracle navOracle;
        /// @notice Fee receiver address
        address feeReceiver;
        /// @notice Fee configuration
        FeeConfig fees;
        /// @notice Performance fee tracking
        uint256 lastNAVForPerformance;
        uint256 lastSupplyForPerformance;
        uint256 lastManagementFeeTimestamp;
        /// @notice High-Water Mark accumulator for performance fee tracking (PPS-based)
        /// @dev Stores the Price Per Share (PPS) at the last point fees were accrued
        /// @dev Stored with 1e18 precision. Fees only charged when PPS increases above this mark
        uint256 ppsTrack;
        /// @notice Accrued performance fees in assets (18 decimals) calculated but not yet minted
        /// @dev Accumulates on every deposit/withdrawal to prevent yield loss with infrequent collections
        /// @dev Only converted to shares when collectPerformanceFee() is called
        uint256 accruedPerformanceFeeInAssets;
        /// @notice Timelock controller for critical operations
        address timeLockController;
        /// @notice Safe manager address
        address safeManager;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.feesManager.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FEE_MANAGER_STORAGE_LOCATION =
        0x4b4022d112866c56e7ce4fba50b143067d70699d5800adf7d8c91134a5bcaf00;

    function _getFeeManagerStorage() private pure returns (FeeManagerStorage storage $) {
        assembly {
            $.slot := FEE_MANAGER_STORAGE_LOCATION
        }
    }

    /// @notice Events
    event PerformanceFeeTaken(uint256 sharesMinted, uint256 feeInAssets, uint256 newHighWatermarkPPS);
    event NoPerformanceFeeTaken(uint256 currentPPS, uint256 highWatermarkPPS);
    event ManagementFeeTaken(uint256 sharesMinted, uint256 annualizedValue, uint256 timestamp);
    event FeeConfigUpdated(uint256 managementFeeBps, uint256 performanceFeeBps);
    event FeeReceiverUpdated(address indexed newReceiver);
    event TimeLockControllerUpdated(address indexed oldTimeLockController, address indexed newTimeLockController);

    /// @notice Modifier for timelock-protected functions
    modifier onlyTimelock() {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        require(msg.sender == $.timeLockController, "FeeManager: only timelock");
        _;
    }

    /// @notice Modifier for safe manager-protected functions
    modifier onlySafeManager() {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        require(msg.sender == $.safeManager, "FeeManager: only safe manager");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the fee manager
     * @dev Ownership (DEFAULT_ADMIN_ROLE) is granted to deployer
     * @param _shareManager Share manager contract
     * @param _navOracle NAV oracle contract
     * @param _feeReceiver Address to receive fees
     * @param _deployer Deployer address (receives DEFAULT_ADMIN_ROLE)
     * @param _safeManager Safe manager address (for operational functions, not ownership)
     * @param _managementFeeBps Annual management fee in basis points
     * @param _performanceFeeBps Performance fee in basis points
     * @param _timeLockController Timelock controller for critical operations
     */
    function initialize(
        address _shareManager,
        address _navOracle,
        address _feeReceiver,
        address _deployer,
        address _safeManager,
        uint256 _managementFeeBps,
        uint256 _performanceFeeBps,
        address _timeLockController
    ) external initializer {
        require(_shareManager != address(0), "FeeManager: zero share manager");
        require(_navOracle != address(0), "FeeManager: zero nav oracle");
        require(_feeReceiver != address(0), "FeeManager: zero fee receiver");
        require(_deployer != address(0), "FeeManager: zero deployer");
        require(_safeManager != address(0), "FeeManager: zero safe manager");
        require(_timeLockController != address(0), "FeeManager: zero timelock");
        require(_managementFeeBps <= 500, "FeeManager: management fee too high"); // Max 5%
        require(_performanceFeeBps <= 3000, "FeeManager: performance fee too high"); // Max 30%

        __AccessControl_init();
        __ReentrancyGuard_init();

        FeeManagerStorage storage $ = _getFeeManagerStorage();
        $.shareManager = IShareManager(_shareManager);
        $.navOracle = INAVOracle(_navOracle);
        $.feeReceiver = _feeReceiver;
        $.timeLockController = _timeLockController;
        $.safeManager = _safeManager;

        $.fees = FeeConfig({managementFeeBps: _managementFeeBps, performanceFeeBps: _performanceFeeBps});

        // Initialize high-water mark accumulator to initial PPS (1e18 = 1.0 share price)
        // This is fair: sets the baseline at the initial share price
        $.ppsTrack = 1e18;
        $.lastNAVForPerformance = $.navOracle.getNAV();
        $.lastSupplyForPerformance = $.shareManager.totalSupply();
        $.lastManagementFeeTimestamp = block.timestamp;

        // Grant ownership to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, _deployer);
        _grantRole(SAFE_MANAGER_ROLE, _safeManager);
    }

    /**
     * @notice Internal function to accrue performance fees without minting shares
     * @dev Called on deposits/withdrawals to checkpoint fees earned so far
     * @dev Prevents yield loss with infrequent collections while avoiding dilution on every deposit
     */
    function _accruePerformanceFee() internal {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        
        if ($.fees.performanceFeeBps == 0) return;
        
        uint256 currentNAV = $.navOracle.getNAV();
        uint256 currentSupply = $.shareManager.totalSupply();
        
        if (currentSupply == 0) return;
        if ($.lastSupplyForPerformance == 0) {
            // First time setup
            $.ppsTrack = currentNAV.mulDiv(1e18, currentSupply, Math.Rounding.Floor);
            $.lastSupplyForPerformance = currentSupply;
            $.lastNAVForPerformance = currentNAV;
            return;
        }
        
        // Calculate current PPS
        uint256 currentPPS = currentNAV.mulDiv(1e18, currentSupply, Math.Rounding.Floor);
        
        // If PPS increased, accrue the fee (but don't mint shares yet)
        if (currentPPS > $.ppsTrack) {
            uint256 ppsIncrease = currentPPS - $.ppsTrack;
            uint256 profitInAssets = ppsIncrease.mulDiv($.lastSupplyForPerformance, 1e18, Math.Rounding.Floor);
            uint256 feeInAssets = profitInAssets.mulDiv($.fees.performanceFeeBps, 10_000, Math.Rounding.Floor);
            
            // Add to accrued fees
            $.accruedPerformanceFeeInAssets += feeInAssets;
            
            // Update checkpoint for next accrual
            $.ppsTrack = currentPPS;
        }
        
        // Always update supply and NAV tracking
        $.lastSupplyForPerformance = currentSupply;
        $.lastNAVForPerformance = currentNAV;
    }

    /**
     * @notice Collect all accrued performance fees by minting shares
     * @dev Accrues any new fees first, then mints shares for all accrued fees
     * @dev This is the ONLY function that actually mints performance fee shares
     * @return sharesMinted Amount of shares minted as fee
     */
    function collectPerformanceFee() external onlySafeManager nonReentrant returns (uint256 sharesMinted) {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        
        // First accrue any new performance fees
        _accruePerformanceFee();
        
        // If no accrued fees, nothing to collect
        if ($.accruedPerformanceFeeInAssets == 0) {
            emit NoPerformanceFeeTaken(0, $.ppsTrack);
            return 0;
        }
        
        uint256 currentNAV = $.navOracle.getNAV();
        uint256 currentSupply = $.shareManager.totalSupply();
        
        if (currentSupply == 0) return 0;
        
        // Convert all accrued fees to shares
        uint256 feeInAssets = $.accruedPerformanceFeeInAssets;
        uint256 navPostFee = currentNAV - feeInAssets;
        sharesMinted = feeInAssets.mulDiv(currentSupply, navPostFee, Math.Rounding.Floor);
        
        if (sharesMinted > 0) {
            $.shareManager.mintFeesShares($.feeReceiver, sharesMinted);
            
            // Reset accrued fees after minting
            $.accruedPerformanceFeeInAssets = 0;
            
            // Update tracking after minting
            $.lastSupplyForPerformance = $.shareManager.totalSupply();
            $.lastNAVForPerformance = currentNAV;
            
            emit PerformanceFeeTaken(sharesMinted, feeInAssets, $.ppsTrack);
        }
        
        return sharesMinted;
    }

    /**
     * @notice Public function to accrue performance fees without collecting them
     * @dev Can be called by DepositPipe/RedemptionPipe before mints/burns
     * @dev Checkpoints fees so they're not lost with infrequent collections
     */
    function accruePerformanceFee() external {
        _accruePerformanceFee();
    }

    /**
     * @notice Collect management fee based on time elapsed
     * @dev Mints shares to fee receiver proportional to time passed
     * @return sharesMinted Amount of shares minted as fee
     */
    function collectManagementFee() external nonReentrant onlySafeManager returns (uint256 sharesMinted) {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        if ($.fees.managementFeeBps == 0) return 0;

        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - $.lastManagementFeeTimestamp;

        // Only collect if more than 1 day has passed
        if (timeElapsed < 1 days) return 0;

        uint256 currentSupply = $.shareManager.totalSupply();
        if (currentSupply == 0) return 0;

        // Calculate annualized management fee with dilution adjustment
        // Formula: shares = supply * feeRate / (1 - feeRate)
        // This ensures fee recipient receives exactly the intended percentage after dilution
        uint256 feeRateNumerator = $.fees.managementFeeBps * timeElapsed;
        uint256 feeRateDenominator = 10_000 * 365 days;

        sharesMinted = currentSupply.mulDiv(
            feeRateNumerator,
            feeRateDenominator - feeRateNumerator,
            Math.Rounding.Floor
        );

        if (sharesMinted > 0) {
            $.shareManager.mintFeesShares($.feeReceiver, sharesMinted);

            // Calculate annualized value for event
            uint256 currentNAV = $.navOracle.getNAV();
            uint256 annualizedValue = currentNAV.mulDiv($.fees.managementFeeBps, 10_000);

            emit ManagementFeeTaken(sharesMinted, annualizedValue, currentTime);

            // Management fee mints dilute PPS without changing NAV.
            // Recalculate and update the PPS-based high-water mark after the dilution.
            // New supply includes the minted management fee shares.
            uint256 newSupply = $.shareManager.totalSupply();
            uint256 newPPS = currentNAV.mulDiv(1e18, newSupply, Math.Rounding.Floor);
            $.ppsTrack = newPPS;
            
            // Also update the tracking variables
            $.lastNAVForPerformance = currentNAV;
            $.lastSupplyForPerformance = newSupply;
        }

        $.lastManagementFeeTimestamp = currentTime;
        return sharesMinted;
    }

    /**
     * @notice Update timelock controller address
     * @param _timelockController New timelock controller address
     */
    function setTimelockController(address _timelockController) external onlyTimelock {
        require(_timelockController != address(0), "FeeManager: zero timelock");
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        address oldTimeLockController = $.timeLockController;
        $.timeLockController = _timelockController;
        emit TimeLockControllerUpdated(oldTimeLockController, _timelockController);
    }

    /**
     * @notice Update fee configuration
     * @param _managementFeeBps New management fee in basis points
     * @param _performanceFeeBps New performance fee in basis points
     */
    function setFees(uint256 _managementFeeBps, uint256 _performanceFeeBps) external onlyTimelock {
        require(_managementFeeBps <= 500, "FeeManager: management fee too high");
        require(_performanceFeeBps <= 3000, "FeeManager: performance fee too high");

        FeeManagerStorage storage $ = _getFeeManagerStorage();
        $.fees.managementFeeBps = _managementFeeBps;
        $.fees.performanceFeeBps = _performanceFeeBps;

        emit FeeConfigUpdated(_managementFeeBps, _performanceFeeBps);
    }

    /**
     * @notice Update fee receiver address
     * @param _feeReceiver New fee receiver address
     */
    function setFeeReceiver(address _feeReceiver) external onlyTimelock {
        require(_feeReceiver != address(0), "FeeManager: zero address");
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        $.feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }

    /**
     * @notice Reset performance fee baseline and PPS high-water mark accumulator
     * @dev Used after significant events or initial setup
     * @dev Resets the high-water mark to current PPS
     */
    function resetPerformanceBaseline() external onlyRole(SAFE_MANAGER_ROLE) {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        uint256 currentNAV = $.navOracle.getNAV();
        uint256 currentSupply = $.shareManager.totalSupply();
        
        uint256 currentPPS;
        if (currentSupply == 0) {
            currentPPS = 1e18; // Default to 1.0 if no shares
        } else {
            currentPPS = currentNAV.mulDiv(1e18, currentSupply, Math.Rounding.Floor);
        }
        
        $.ppsTrack = currentPPS;
        $.lastNAVForPerformance = currentNAV;
        $.lastSupplyForPerformance = currentSupply;
    }


    /**
     * @notice Get current fee configuration
     * @return managementFeeBps Annual management fee in basis points
     * @return performanceFeeBps Performance fee in basis points
     */
    function getFees() external view returns (uint256 managementFeeBps, uint256 performanceFeeBps) {
        FeeManagerStorage storage $ = _getFeeManagerStorage();
        return ($.fees.managementFeeBps, $.fees.performanceFeeBps);
    }

    /// @notice Get last NAV for performance fee calculation
    function lastNAVForPerformance() external view returns (uint256) {
        return _getFeeManagerStorage().lastNAVForPerformance;
    }

    /// @notice Get last supply for performance fee calculation
    function lastSupplyForPerformance() external view returns (uint256) {
        return _getFeeManagerStorage().lastSupplyForPerformance;
    }

    /// @notice Get last management fee timestamp
    function lastManagementFeeTimestamp() external view returns (uint256) {
        return _getFeeManagerStorage().lastManagementFeeTimestamp;
    }

    /// @notice Get fee receiver address
    function feeReceiver() external view returns (address) {
        return _getFeeManagerStorage().feeReceiver;
    }

    /// @notice Get timelock controller address
    function timeLockController() external view returns (address) {
        return _getFeeManagerStorage().timeLockController;
    }

    /// @notice Get high-water mark accumulator (PPS at last performance fee collection, stored with 1e18 precision)
    function highWatermarkPPS() external view returns (uint256) {
        return _getFeeManagerStorage().ppsTrack;
    }

    /// @notice Get accrued performance fees in assets (18 decimals) not yet minted as shares
    function accruedPerformanceFeeInAssets() external view returns (uint256) {
        return _getFeeManagerStorage().accruedPerformanceFeeInAssets;
    }
}
