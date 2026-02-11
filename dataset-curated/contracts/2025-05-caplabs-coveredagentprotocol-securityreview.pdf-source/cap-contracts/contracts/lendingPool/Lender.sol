// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Access } from "../access/Access.sol";

import { ILender } from "../interfaces/ILender.sol";
import { LenderStorageUtils } from "../storage/LenderStorageUtils.sol";
import { BorrowLogic } from "./libraries/BorrowLogic.sol";
import { LiquidationLogic } from "./libraries/LiquidationLogic.sol";
import { ReserveLogic } from "./libraries/ReserveLogic.sol";
import { ViewLogic } from "./libraries/ViewLogic.sol";

/// @title Lender for covered agents
/// @author kexley, @capLabs
/// @notice Whitelisted tokens are borrowed and repaid from this contract by covered agents.
/// @dev Borrow interest rates are calculated from the underlying utilization rates of the assets
/// in the vaults.
contract Lender is ILender, UUPSUpgradeable, Access, LenderStorageUtils {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the lender
    /// @param _accessControl Access control address
    /// @param _delegation Delegation address
    /// @param _oracle Oracle address
    /// @param _targetHealth Target health after liquidations (scaled by 1e27)
    /// @param _grace Grace period in seconds before an agent becomes liquidatable
    /// @param _expiry Expiry period in seconds after which an agent cannot be liquidated until called again
    /// @param _bonusCap Bonus cap for liquidations (scaled by 1e27)
    /// @param _emergencyLiquidationThreshold Liquidation threshold below which grace periods are voided (scaled by 1e27)
    function initialize(
        address _accessControl,
        address _delegation,
        address _oracle,
        uint256 _targetHealth,
        uint256 _grace,
        uint256 _expiry,
        uint256 _bonusCap,
        uint256 _emergencyLiquidationThreshold
    ) external initializer {
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();

        if (_delegation == address(0) || _oracle == address(0)) revert ZeroAddressNotValid();
        if (_grace > _expiry) revert GracePeriodGreaterThanExpiry();

        LenderStorage storage $ = getLenderStorage();
        $.delegation = _delegation;
        $.oracle = _oracle;
        $.targetHealth = _targetHealth;
        $.grace = _grace;
        $.expiry = _expiry;
        $.bonusCap = _bonusCap;
        $.emergencyLiquidationThreshold = _emergencyLiquidationThreshold;
    }

    /// @notice Borrow an asset
    /// @param _asset Asset to borrow
    /// @param _amount Amount to borrow
    /// @param _receiver Receiver of the borrowed asset
    function borrow(address _asset, uint256 _amount, address _receiver) external {
        BorrowLogic.borrow(
            getLenderStorage(), BorrowParams({ agent: msg.sender, asset: _asset, amount: _amount, receiver: _receiver })
        );
    }

    /// @notice Repay an asset
    /// @param _asset Asset to repay
    /// @param _amount Amount to repay
    /// @param _agent Repay on behalf of another borrower
    /// @return repaid Actual amount repaid
    function repay(address _asset, uint256 _amount, address _agent) external returns (uint256 repaid) {
        if (_agent == address(0) || _asset == address(0)) revert ZeroAddressNotValid();
        repaid = BorrowLogic.repay(
            getLenderStorage(), RepayParams({ agent: _agent, asset: _asset, amount: _amount, caller: msg.sender })
        );
    }

    /// @notice Realize interest for an asset
    /// @param _asset Asset to realize interest for
    /// @return actualRealized Actual amount realized
    function realizeInterest(address _asset) external returns (uint256 actualRealized) {
        actualRealized = BorrowLogic.realizeInterest(getLenderStorage(), _asset);
    }

    /// @notice Realize interest for restaker debt of an agent for an asset
    /// @param _agent Agent to realize interest for
    /// @param _asset Asset to realize interest for
    /// @return actualRealized Actual amount realized
    function realizeRestakerInterest(address _agent, address _asset) external returns (uint256 actualRealized) {
        actualRealized = BorrowLogic.realizeRestakerInterest(getLenderStorage(), _agent, _asset);
    }

    /// @notice Calculate the maximum interest that can be realized
    /// @param _asset Asset to calculate max realization for
    /// @return _maxRealization Maximum interest that can be realized
    function maxRealization(address _asset) external view returns (uint256 _maxRealization) {
        _maxRealization = BorrowLogic.maxRealization(getLenderStorage(), _asset);
    }

    /// @notice Calculate the maximum interest that can be realized for a restaker
    /// @param _agent Agent to calculate max realization for
    /// @param _asset Asset to calculate max realization for
    /// @return newRealizedInterest Maximum interest that can be realized
    /// @return newUnrealizedInterest Unrealized interest that will be added to the debt
    function maxRestakerRealization(address _agent, address _asset)
        external
        view
        returns (uint256 newRealizedInterest, uint256 newUnrealizedInterest)
    {
        (newRealizedInterest, newUnrealizedInterest) =
            BorrowLogic.maxRestakerRealization(getLenderStorage(), _agent, _asset);
    }

    /// @notice Initiate liquidation of an agent when the health is below 1
    /// @param _agent Agent address
    function initiateLiquidation(address _agent) external {
        LiquidationLogic.initiateLiquidation(getLenderStorage(), _agent);
    }

    /// @notice Cancel liquidation of an agent when the health is above 1
    /// @param _agent Agent address
    function cancelLiquidation(address _agent) external {
        LiquidationLogic.cancelLiquidation(getLenderStorage(), _agent);
    }

    /// @notice Liquidate an agent when the health is below 1
    /// @param _agent Agent address
    /// @param _asset Asset to repay
    /// @param _amount Amount of asset to repay on behalf of the agent
    /// @param liquidatedValue Value of the liquidation returned to the liquidator
    function liquidate(address _agent, address _asset, uint256 _amount) external returns (uint256 liquidatedValue) {
        if (_agent == address(0) || _asset == address(0)) revert ZeroAddressNotValid();
        liquidatedValue = LiquidationLogic.liquidate(
            getLenderStorage(), RepayParams({ agent: _agent, asset: _asset, amount: _amount, caller: msg.sender })
        );
    }

    /// @notice Calculate the agent data
    /// @param _agent Address of agent
    /// @return totalDelegation Total delegation of an agent in USD, encoded with 8 decimals
    /// @return totalSlashableCollateral Total slashable collateral of an agent in USD, encoded with 8 decimals
    /// @return totalDebt Total debt of an agent in USD, encoded with 8 decimals
    /// @return ltv Loan to value ratio, encoded in ray (1e27)
    /// @return liquidationThreshold Liquidation ratio of an agent, encoded in ray (1e27)
    /// @return health Health status of an agent, encoded in ray (1e27)
    function agent(address _agent)
        external
        view
        returns (
            uint256 totalDelegation,
            uint256 totalSlashableCollateral,
            uint256 totalDebt,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 health
        )
    {
        (totalDelegation, totalSlashableCollateral, totalDebt, ltv, liquidationThreshold, health) =
            ViewLogic.agent(getLenderStorage(), _agent);
    }

    /// @notice Calculate the maximum amount that can be borrowed for a given asset
    /// @param _agent Agent address
    /// @param _asset Asset to borrow
    /// @return maxBorrowableAmount Maximum amount that can be borrowed in asset decimals
    function maxBorrowable(address _agent, address _asset) external view returns (uint256 maxBorrowableAmount) {
        if (_agent == address(0) || _asset == address(0)) revert ZeroAddressNotValid();
        maxBorrowableAmount = ViewLogic.maxBorrowable(getLenderStorage(), _agent, _asset);
    }

    /// @notice Calculate the maximum amount that can be liquidated for a given asset
    /// @param _agent Agent address
    /// @param _asset Asset to liquidate
    /// @return maxLiquidatableAmount Maximum amount that can be liquidated in asset decimals
    function maxLiquidatable(address _agent, address _asset) external view returns (uint256 maxLiquidatableAmount) {
        if (_agent == address(0) || _asset == address(0)) revert ZeroAddressNotValid();
        maxLiquidatableAmount = ViewLogic.maxLiquidatable(getLenderStorage(), _agent, _asset);
    }

    /// @notice Get the current debt balances for an agent for a specific asset
    /// @param _agent Agent address to check debt for
    /// @param _asset Asset to check debt for
    /// @return totalDebt Total debt amount in asset decimals
    function debt(address _agent, address _asset) external view returns (uint256 totalDebt) {
        if (_agent == address(0) || _asset == address(0)) revert ZeroAddressNotValid();
        totalDebt = ViewLogic.debt(getLenderStorage(), _agent, _asset);
    }

    /// @notice Get the accrued restaker interest for an agent for a specific asset
    /// @param _agent Agent address to check accrued restaker interest for
    /// @param _asset Asset to check accrued restaker interest for
    /// @return accruedInterest Accrued restaker interest in asset decimals
    function accruedRestakerInterest(address _agent, address _asset) external view returns (uint256 accruedInterest) {
        if (_agent == address(0) || _asset == address(0)) revert ZeroAddressNotValid();
        accruedInterest = ViewLogic.accruedRestakerInterest(getLenderStorage(), _agent, _asset);
    }

    /// @notice Add an asset to the Lender
    /// @param _params Parameters to add an asset
    function addAsset(AddAssetParams calldata _params) external checkAccess(this.addAsset.selector) {
        LenderStorage storage $ = getLenderStorage();
        if (!ReserveLogic.addAsset($, _params)) ++$.reservesCount;
    }

    /// @notice Remove asset from lending when there is no borrows
    /// @param _asset Asset address
    function removeAsset(address _asset) external checkAccess(this.removeAsset.selector) {
        if (_asset == address(0)) revert ZeroAddressNotValid();
        ReserveLogic.removeAsset(getLenderStorage(), _asset);
    }

    /// @notice Pause an asset from being borrowed
    /// @param _asset Asset address
    /// @param _pause True if pausing or false if unpausing
    function pauseAsset(address _asset, bool _pause) external checkAccess(this.pauseAsset.selector) {
        if (_asset == address(0)) revert ZeroAddressNotValid();
        ReserveLogic.pauseAsset(getLenderStorage(), _asset, _pause);
    }

    /// @notice Set the minimum borrow amount for an asset
    /// @param _asset Asset address
    /// @param _minBorrow Minimum borrow amount
    function setMinBorrow(address _asset, uint256 _minBorrow) external checkAccess(this.setMinBorrow.selector) {
        if (_asset == address(0)) revert ZeroAddressNotValid();
        ReserveLogic.setMinBorrow(getLenderStorage(), _asset, _minBorrow);
    }

    /// @notice The total number of reserves
    /// @return count Number of reserves
    function reservesCount() external view returns (uint256 count) {
        count = getLenderStorage().reservesCount;
    }

    /// @notice The grace period duration
    /// @return gracePeriod Grace period in seconds
    function grace() external view returns (uint256 gracePeriod) {
        gracePeriod = getLenderStorage().grace;
    }

    /// @notice The expiry period duration
    /// @return expiryPeriod Expiry period in seconds
    function expiry() external view returns (uint256 expiryPeriod) {
        expiryPeriod = getLenderStorage().expiry;
    }

    /// @notice The target health factor
    /// @return target Target health factor scaled to 1e27
    function targetHealth() external view returns (uint256 target) {
        target = getLenderStorage().targetHealth;
    }

    /// @notice The liquidation bonus cap
    /// @return cap Bonus cap scaled to 1e27
    function bonusCap() external view returns (uint256 cap) {
        cap = getLenderStorage().bonusCap;
    }

    /// @notice The emergency liquidation threshold
    /// @return threshold Threshold scaled to 1e27
    function emergencyLiquidationThreshold() external view returns (uint256 threshold) {
        threshold = getLenderStorage().emergencyLiquidationThreshold;
    }

    /// @notice The liquidation start time for an agent
    /// @param _agent Address of the agent
    /// @return startTime Timestamp when liquidation was initiated
    function liquidationStart(address _agent) external view returns (uint256 startTime) {
        startTime = getLenderStorage().liquidationStart[_agent];
    }

    /// @notice The reserve data for an asset
    /// @param _asset Address of the asset
    /// @return id Id of the reserve
    /// @return vault Address of the vault
    /// @return debtToken Address of the debt token
    /// @return interestReceiver Address of the interest receiver
    /// @return decimals Decimals of the asset
    /// @return paused True if the asset is paused, false otherwise
    function reservesData(address _asset)
        external
        view
        returns (
            uint256 id,
            address vault,
            address debtToken,
            address interestReceiver,
            uint8 decimals,
            bool paused,
            uint256 minBorrow
        )
    {
        ReserveData storage reserve = getLenderStorage().reservesData[_asset];
        id = reserve.id;
        vault = reserve.vault;
        debtToken = reserve.debtToken;
        interestReceiver = reserve.interestReceiver;
        decimals = reserve.decimals;
        paused = reserve.paused;
        minBorrow = reserve.minBorrow;
    }

    /// @notice The unrealized restaker interest for an agent and asset
    /// @param _agent Address of the agent
    /// @param _asset Address of the asset
    /// @return _unrealizedInterest Unrealized interest scaled to 1e27
    function unrealizedInterest(address _agent, address _asset) external view returns (uint256 _unrealizedInterest) {
        ReserveData storage reserve = getLenderStorage().reservesData[_asset];
        _unrealizedInterest = reserve.unrealizedInterest[_agent];
    }

    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
