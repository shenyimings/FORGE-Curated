// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @title AccountantWithRateProviders
 */
contract AccountantWithRateProviders is Auth, IRateProvider {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // ========================================= STRUCTS =========================================

    /**
     * @param payoutAddress the address `claimFees` sends fees to
     * @param feesOwedInBase total pending fees owed in terms of base
     * @param totalSharesLastUpdate total amount of shares the last exchange rate update
     * @param exchangeRate the current exchange rate in terms of base
     * @param _allowedExchangeRateChangeUpper the max allowed change to exchange rate from an update
     * @param _allowedExchangeRateChangeLower the min allowed change to exchange rate from an update
     * @param _lastUpdateTimestamp the block timestamp of the last exchange rate update
     * @param _isPaused whether or not this contract is paused
     * @param _minimumUpdateDelayInSeconds the minimum amount of time that must pass between
     *        exchange rate updates, such that the update won't trigger the contract to be paused
     * @param _managementFee the management fee
     */
    struct AccountantState {
        address _payoutAddress;
        uint128 _feesOwedInBase;
        uint128 _totalSharesLastUpdate;
        uint96 _exchangeRate;
        uint16 _allowedExchangeRateChangeUpper;
        uint16 _allowedExchangeRateChangeLower;
        uint64 _lastUpdateTimestamp;
        bool _isPaused;
        uint32 _minimumUpdateDelayInSeconds;
        uint16 _managementFee;
    }

    /**
     * @notice Lending specific state
     * @param _lendingRate Annual lending interest rate in basis points (1000 = 10%)
     * @param _lastAccrualTime Timestamp of last interest accrual
     */
    struct LendingInfo {
        uint256 _lendingRate; // Rate for vault growth
        uint256 _lastAccrualTime; // Last checkpoint
    }

    /**
     * @param isPeggedToBase whether or not the asset is 1:1 with the base asset
     * @param rateProvider the rate provider for this asset if `isPeggedToBase` is false
     */
    struct RateProviderData {
        bool isPeggedToBase;
        IRateProvider rateProvider;
    }

    // ========================================= CONSTANTS =========================================
    // Constants for calculations
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant BASIS_POINTS = 10_000;

    // ========================================= STATE =========================================

    /**
     * @notice Store the accountant state in 3 packed slots.
     */
    AccountantState public accountantState;
    LendingInfo public lendingInfo;
    uint256 public maxLendingRate;

    /**
     * @notice Maps ERC20s to their RateProviderData.
     */
    mapping(ERC20 => RateProviderData) public rateProviderData;

    //============================== ERRORS ===============================

    error AccountantWithRateProviders__UpperBoundTooSmall();
    error AccountantWithRateProviders__LowerBoundTooLarge();
    error AccountantWithRateProviders__ManagementFeeTooLarge();
    error AccountantWithRateProviders__Paused();
    error AccountantWithRateProviders__ZeroFeesOwed();
    error AccountantWithRateProviders__OnlyCallableByBoringVault();
    error AccountantWithRateProviders__UpdateDelayTooLarge();
    error AccountantWithRateProviders__UpperMustExceedLower();

    //============================== EVENTS ===============================

    event Paused();
    event Unpaused();
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);
    event UpperBoundUpdated(uint16 oldBound, uint16 newBound);
    event LowerBoundUpdated(uint16 oldBound, uint16 newBound);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);
    event FeesClaimed(address indexed feeAsset, uint256 amount);
    event LendingRateUpdated(uint256 newRate, uint256 timestamp);
    event ManagementFeeRateUpdated(uint16 newRate, uint256 timestamp);
    event MaxLendingRateUpdated(uint256 newMaxRate);
    event Checkpoint(uint256 indexed timestamp);

    //============================== IMMUTABLES ===============================

    /**
     * @notice The base asset rates are provided in.
     */
    ERC20 public immutable base;

    /**
     * @notice The decimals rates are provided in.
     */
    uint8 public immutable decimals;

    /**
     * @notice The BoringVault this accountant is working with.
     *         Used to determine share supply for fee calculation.
     */
    BoringVault public immutable vault;

    /**
     * @notice One share of the BoringVault.
     */
    uint256 internal immutable ONE_SHARE;

    constructor(
        address _owner,
        address _vault,
        address _payoutAddress,
        uint96 _startingExchangeRate,
        address _base,
        uint16 _allowedExchangeRateChangeUpper,
        uint16 _allowedExchangeRateChangeLower,
        uint32 _minimumUpdateDelayInSeconds,
        uint16 _managementFee
    )
        Auth(_owner, Authority(address(0)))
    {
        base = ERC20(_base);
        decimals = ERC20(_base).decimals();
        vault = BoringVault(payable(_vault));
        ONE_SHARE = 10 ** vault.decimals();
        accountantState = AccountantState({
            _payoutAddress: _payoutAddress,
            _feesOwedInBase: 0,
            _totalSharesLastUpdate: uint128(vault.totalSupply()),
            _exchangeRate: _startingExchangeRate,
            _allowedExchangeRateChangeUpper: _allowedExchangeRateChangeUpper,
            _allowedExchangeRateChangeLower: _allowedExchangeRateChangeLower,
            _lastUpdateTimestamp: uint64(block.timestamp),
            _isPaused: false,
            _minimumUpdateDelayInSeconds: _minimumUpdateDelayInSeconds,
            _managementFee: _managementFee
        });
        lendingInfo._lastAccrualTime = block.timestamp;
        maxLendingRate = 5000;
    }

    // ========================================= ADMIN FUNCTIONS =========================================
    /**
     * @notice Pause this contract, which prevents future calls to `updateExchangeRate`, and any safe rate
     *         calls will revert.
     * @dev Pausing only prevents state changes, not time-based calculations
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() public requiresAuth {
        accountantState._isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `updateExchangeRate`, and any safe rate
     *         calls will stop reverting.
     * @dev Callable by MULTISIG_ROLE.
     */
    function unpause() external requiresAuth {
        accountantState._isPaused = false;
        emit Unpaused();
    }

    /**
     * @notice Update the minimum time delay between `updateExchangeRate` calls.
     * @dev There are no input requirements, as it is possible the admin would want
     *      the exchange rate updated as frequently as needed.
     * @dev Callable by OWNER_ROLE.
     */
    function updateDelay(uint32 _minimumUpdateDelayInSeconds) external requiresAuth {
        if (_minimumUpdateDelayInSeconds > 14 days) revert AccountantWithRateProviders__UpdateDelayTooLarge();
        uint32 oldDelay = accountantState._minimumUpdateDelayInSeconds;
        accountantState._minimumUpdateDelayInSeconds = _minimumUpdateDelayInSeconds;
        emit DelayInSecondsUpdated(oldDelay, _minimumUpdateDelayInSeconds);
    }

    /**
     * @notice Update the allowed upper bound change of exchange rate between `updateExchangeRateCalls`.
     * @dev Callable by OWNER_ROLE.
     */
    function updateUpper(uint16 _allowedExchangeRateChangeUpper) external requiresAuth {
        if (_allowedExchangeRateChangeUpper <= accountantState._allowedExchangeRateChangeLower) {
            revert AccountantWithRateProviders__UpperMustExceedLower();
        }
        if (_allowedExchangeRateChangeUpper < BASIS_POINTS) revert AccountantWithRateProviders__UpperBoundTooSmall();
        uint16 oldBound = accountantState._allowedExchangeRateChangeUpper;
        accountantState._allowedExchangeRateChangeUpper = _allowedExchangeRateChangeUpper;
        emit UpperBoundUpdated(oldBound, _allowedExchangeRateChangeUpper);
    }

    /**
     * @notice Update the allowed lower bound change of exchange rate between `updateExchangeRateCalls`.
     * @dev Callable by OWNER_ROLE.
     */
    function updateLower(uint16 _allowedExchangeRateChangeLower) external requiresAuth {
        if (_allowedExchangeRateChangeLower >= accountantState._allowedExchangeRateChangeUpper) {
            revert AccountantWithRateProviders__UpperMustExceedLower();
        }
        if (_allowedExchangeRateChangeLower > BASIS_POINTS) revert AccountantWithRateProviders__LowerBoundTooLarge();
        uint16 oldBound = accountantState._allowedExchangeRateChangeLower;
        accountantState._allowedExchangeRateChangeLower = _allowedExchangeRateChangeLower;
        emit LowerBoundUpdated(oldBound, _allowedExchangeRateChangeLower);
    }

    /**
     * @notice Update the payout address fees are sent to.
     * @dev Callable by OWNER_ROLE.
     */
    function updatePayoutAddress(address _payoutAddress) external requiresAuth {
        address oldPayout = accountantState._payoutAddress;
        accountantState._payoutAddress = _payoutAddress;
        emit PayoutAddressUpdated(oldPayout, _payoutAddress);
    }

    /**
     * @notice Update the rate provider data for a specific `asset`.
     * @dev Rate providers must return rates in terms of `base`
     * @dev Rate providers MUST ALWAYS return rates in 18 decimals regardless of asset decimals
     * @dev The rate should represent how much base value 1 unit of asset is worth
     * @dev Callable by OWNER_ROLE.
     */
    function setRateProviderData(ERC20 _asset, bool _isPeggedToBase, address _rateProvider) external requiresAuth {
        rateProviderData[_asset] =
            RateProviderData({ isPeggedToBase: _isPeggedToBase, rateProvider: IRateProvider(_rateProvider) });
        emit RateProviderUpdated(address(_asset), _isPeggedToBase, _rateProvider);
    }

    // ========================================= UPDATE EXCHANGE RATE/FEES FUNCTIONS
    // =========================================

    /**
     * @notice Updates this contract exchangeRate.
     * @dev If new exchange rate is outside of accepted bounds, or if not enough time has passed, this
     *      will pause the contract, and this function will NOT calculate fees owed.
     * @dev Callable by UPDATE_EXCHANGE_RATE_ROLE.
     */
    function updateExchangeRate(uint96 _newExchangeRate) external requiresAuth {
        AccountantState storage state = accountantState;

        uint64 currentTime = uint64(block.timestamp);
        (uint96 currentRateWithInterest,) = calculateExchangeRateWithInterest();

        uint96 oldExchangeRate = state._exchangeRate;

        _checkpointInterestAndFees();

        uint256 currentTotalShares = vault.totalSupply();

        if (
            currentTime < state._lastUpdateTimestamp + state._minimumUpdateDelayInSeconds
                || _newExchangeRate
                    > uint256(currentRateWithInterest).mulDivDown(state._allowedExchangeRateChangeUpper, BASIS_POINTS)
                || _newExchangeRate
                    < uint256(currentRateWithInterest).mulDivDown(state._allowedExchangeRateChangeLower, BASIS_POINTS)
        ) {
            pause();
        }

        // Always update the rate and timestamp
        state._exchangeRate = _newExchangeRate;
        state._totalSharesLastUpdate = uint128(currentTotalShares);
        state._lastUpdateTimestamp = currentTime;

        emit ExchangeRateUpdated(oldExchangeRate, _newExchangeRate, currentTime);
    }

    /**
     * @notice Set lending rate
     * @dev Checkpoints current interest and management fees before changing rate
     * @dev This prevents loss of accrued value when rate changes
     * @param _lendingRate New lending rate in basis points (1000 = 10% APY)
     */
    function setLendingRate(uint256 _lendingRate) external requiresAuth {
        require(_lendingRate <= maxLendingRate, "Lending rate exceeds maximum");

        // Checkpoint both interest and fees before rate change
        _checkpointInterestAndFees();

        lendingInfo._lendingRate = _lendingRate;
        emit LendingRateUpdated(_lendingRate, block.timestamp);
    }

    /**
     * @notice Set management fee rate (requires checkpoint)
     * @dev Checkpoints current management fees at old rate before changing
     * @dev This ensures fees are correctly attributed to each rate period
     * @param _managementFeeRate New management fee rate in basis points
     */
    function setManagementFeeRate(uint16 _managementFeeRate) external requiresAuth {
        if (_managementFeeRate > 0.2e4) revert AccountantWithRateProviders__ManagementFeeTooLarge();
        _checkpointInterestAndFees();

        accountantState._managementFee = _managementFeeRate;
        emit ManagementFeeRateUpdated(_managementFeeRate, block.timestamp);
    }

    /**
     * @notice Set maximum lending rate
     * @dev Callable by OWNER_ROLE
     */
    function setMaxLendingRate(uint256 _maxLendingRate) external requiresAuth {
        _checkpointInterestAndFees();
        maxLendingRate = _maxLendingRate;

        // Adjust current rate if needed
        if (lendingInfo._lendingRate > _maxLendingRate) {
            lendingInfo._lendingRate = _maxLendingRate;
            emit LendingRateUpdated(_maxLendingRate, block.timestamp);
        }

        emit MaxLendingRateUpdated(_maxLendingRate);
    }

    /**
     * @notice Claim pending fees.
     * @dev This function must be called by the BoringVault.
     * @dev This function will lose precision if the exchange rate
     *      decimals is greater than the _feeAsset's decimals.
     */
    function claimFees(ERC20 _feeAsset) external {
        if (msg.sender != address(vault)) revert AccountantWithRateProviders__OnlyCallableByBoringVault();

        AccountantState storage state = accountantState;
        if (state._isPaused) revert AccountantWithRateProviders__Paused();

        _checkpointInterestAndFees();

        if (state._feesOwedInBase == 0) revert AccountantWithRateProviders__ZeroFeesOwed();

        // Determine amount of fees owed in _feeAsset
        uint256 feesOwedInFeeAsset;
        RateProviderData memory data = rateProviderData[_feeAsset];
        if (address(_feeAsset) == address(base)) {
            feesOwedInFeeAsset = state._feesOwedInBase;
        } else {
            uint8 feeAssetDecimals = ERC20(_feeAsset).decimals();
            uint256 feesOwedInBaseUsingFeeAssetDecimals =
                _changeDecimals(state._feesOwedInBase, decimals, feeAssetDecimals);
            if (data.isPeggedToBase) {
                feesOwedInFeeAsset = feesOwedInBaseUsingFeeAssetDecimals;
            } else {
                uint256 rate = data.rateProvider.getRate();
                feesOwedInFeeAsset = feesOwedInBaseUsingFeeAssetDecimals.mulDivDown(10 ** 18, rate);
            }
        }

        // Zero out fees owed
        state._feesOwedInBase = 0;

        // Transfer fee asset to payout address
        _feeAsset.safeTransferFrom(msg.sender, state._payoutAddress, feesOwedInFeeAsset);

        emit FeesClaimed(address(_feeAsset), feesOwedInFeeAsset);
    }

    // ========================================= RATE FUNCTIONS =========================================

    /**
     * @notice Get this BoringVault's current rate in the base (real-time with interest).
     */
    function getRate() public view returns (uint256 rate) {
        (uint96 currentRate,) = calculateExchangeRateWithInterest();
        return currentRate;
    }

    /**
     * @notice Calculate current exchange rate including accrued interest
     * @dev This is a view function - interest continues accruing even when paused
     * @return newRate The exchange rate including accrued interest
     * @return interestAccrued The amount of interest accrued since last checkpoint
     */
    function calculateExchangeRateWithInterest() public view returns (uint96 newRate, uint256 interestAccrued) {
        newRate = accountantState._exchangeRate;

        if (lendingInfo._lendingRate > 0) {
            uint256 timeElapsed = block.timestamp - lendingInfo._lastAccrualTime;

            // Calculate rate increase in 18 decimals
            uint256 rateIncrease = uint256(accountantState._exchangeRate).mulDivDown(
                lendingInfo._lendingRate * timeElapsed, SECONDS_PER_YEAR * BASIS_POINTS
            );
            newRate = accountantState._exchangeRate + uint96(rateIncrease);

            // Interest accrued is only for actual deposits
            if (vault.totalSupply() > 0) {
                // Calculate in 18 decimals, then convert to base decimals
                uint256 totalDepositsIn18 = vault.totalSupply().mulDivDown(newRate, ONE_SHARE);
                uint256 totalDeposits = _changeDecimals(totalDepositsIn18, 18, decimals);

                interestAccrued =
                    totalDeposits.mulDivDown(lendingInfo._lendingRate * timeElapsed, SECONDS_PER_YEAR * BASIS_POINTS);
            }
        }
    }

    /**
     * @notice Get this BoringVault's current rate in the base.
     * @dev Revert if paused.
     */
    function getRateSafe() external view returns (uint256 rate) {
        if (accountantState._isPaused) revert AccountantWithRateProviders__Paused();
        (uint96 currentRate,) = calculateExchangeRateWithInterest();
        rate = currentRate;
    }

    /**
     * @notice Get this BoringVault's current rate in the provided quote.
     * @dev `quote` must have its RateProviderData set, else this will revert.
     * @dev This function will lose precision if the exchange rate
     *      decimals is greater than the _quote's decimals.
     */
    function getRateInQuote(ERC20 _quote) public view returns (uint256 rateInQuote) {
        // Get real-time rate in 18 decimals
        (uint96 currentRate,) = calculateExchangeRateWithInterest();

        if (address(_quote) == address(base)) {
            // Convert from 18 decimals to base decimals for display
            rateInQuote = _changeDecimals(currentRate, 18, decimals);
        } else {
            RateProviderData memory data = rateProviderData[_quote];
            uint8 quoteDecimals = ERC20(_quote).decimals();

            if (data.isPeggedToBase) {
                // Convert from 18 decimals to quote decimals
                rateInQuote = _changeDecimals(currentRate, 18, quoteDecimals);
            } else {
                // Rate provider should return 18 decimals
                uint256 quoteRate = data.rateProvider.getRate();
                // Calculate: currentRate * 1e18 / quoteRate, then scale to quote decimals
                uint256 rateInQuote18 = uint256(currentRate).mulDivDown(1e18, quoteRate);
                rateInQuote = _changeDecimals(rateInQuote18, 18, quoteDecimals);
            }
        }
    }

    /**
     * @notice Get this BoringVault's current rate in the provided quote.
     * @dev `quote` must have its RateProviderData set, else this will revert.
     * @dev Revert if paused.
     */
    function getRateInQuoteSafe(ERC20 _quote) external view returns (uint256 rateInQuote) {
        if (accountantState._isPaused) revert AccountantWithRateProviders__Paused();
        rateInQuote = getRateInQuote(_quote);
    }

    /**
     * @notice Get total rate paid by borrower
     * @dev This is the sum of lending rate (for depositors) and management fee rate
     * @return Total borrower rate in basis points
     */
    function getBorrowerRate() public view returns (uint256) {
        return lendingInfo._lendingRate + accountantState._managementFee;
    }

    /**
     * @notice Preview total management fees owed including unclaimed
     * @dev Calculates real-time fees without modifying state
     * @dev Includes both stored fees and fees accrued since last checkpoint
     * @return totalFees Total management fees owed in base asset
     */
    function previewFeesOwed() external view returns (uint256 totalFees) {
        totalFees = accountantState._feesOwedInBase;

        if (vault.totalSupply() > 0 && accountantState._managementFee > 0) {
            uint256 timeElapsed = block.timestamp - lendingInfo._lastAccrualTime;

            (uint96 currentRate,) = calculateExchangeRateWithInterest();
            uint256 totalDepositsIn18 = vault.totalSupply().mulDivDown(currentRate, ONE_SHARE);
            // Convert to base decimals for fee calculation
            uint256 totalDeposits = _changeDecimals(totalDepositsIn18, 18, decimals);

            uint256 managementFees =
                totalDeposits.mulDivDown(accountantState._managementFee * timeElapsed, SECONDS_PER_YEAR * BASIS_POINTS);
            totalFees += managementFees;
        }
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================
    /**
     * @notice Checkpoint both interest and management fees
     * @dev Updates exchange rate with interest and feesOwedInBase with management fees
     */
    function _checkpointInterestAndFees() internal {
        uint256 timeElapsed = block.timestamp - lendingInfo._lastAccrualTime;
        if (timeElapsed > 0) {
            (uint96 newRate,) = calculateExchangeRateWithInterest();
            accountantState._exchangeRate = newRate;

            // Only calculate management fees when there are actual deposits
            if (vault.totalSupply() > 0 && accountantState._managementFee > 0) {
                // Calculate value in 18 decimals, then convert to base decimals for fee storage
                uint256 totalValueIn18 = vault.totalSupply().mulDivDown(newRate, ONE_SHARE);
                uint256 totalValue = _changeDecimals(totalValueIn18, 18, decimals);

                uint256 managementFees =
                    totalValue.mulDivDown(accountantState._managementFee * timeElapsed, SECONDS_PER_YEAR * BASIS_POINTS);
                accountantState._feesOwedInBase += uint128(managementFees);
            }
            lendingInfo._lastAccrualTime = block.timestamp;
            emit Checkpoint(block.timestamp);
        }
    }

    /**
     * @notice Updates the stored exchange rate and accrues management fees
     * @dev Should be called before any operation that depends on the current exchange rate
     * @dev This includes deposits, withdrawals, and fee calculations
     * @dev Callable by authorized contracts (Teller) to ensure rate consistency
     */
    function checkpoint() external requiresAuth {
        require(!accountantState._isPaused, "Cannot checkpoint when paused");
        _checkpointInterestAndFees();
    }

    /**
     * @notice Used to change the decimals of precision used for an amount.
     */
    function _changeDecimals(uint256 _amount, uint8 _fromDecimals, uint8 _toDecimals) internal pure returns (uint256) {
        if (_fromDecimals == _toDecimals) {
            return _amount;
        } else if (_fromDecimals < _toDecimals) {
            return _amount * 10 ** (_toDecimals - _fromDecimals);
        } else {
            return _amount / 10 ** (_fromDecimals - _toDecimals);
        }
    }
}
