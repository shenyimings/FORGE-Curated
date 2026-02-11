// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

// interfaces
import {IRoles} from "src/interfaces/IRoles.sol";
import {ImToken, ImTokenMinimal} from "src/interfaces/ImToken.sol";
import {IInterestRateModel} from "src/interfaces/IInterestRateModel.sol";

// contracts
import {ExponentialNoError} from "src/utils/ExponentialNoError.sol";

abstract contract mTokenStorage is ImToken, ExponentialNoError {
    // ----------- ACCESS STORAGE ------------
    /**
     * @inheritdoc ImToken
     */
    address payable public admin;

    /**
     * @inheritdoc ImToken
     */
    address payable public pendingAdmin;

    /**
     * @inheritdoc ImToken
     */
    address public operator;

    /**
     * @inheritdoc ImToken
     */
    IRoles public rolesOperator;

    // ----------- TOKENS STORAGE ------------
    /**
     * @inheritdoc ImTokenMinimal
     */
    string public name;

    /**
     * @inheritdoc ImTokenMinimal
     */
    string public symbol;

    /**
     * @inheritdoc ImTokenMinimal
     */
    uint8 public decimals;

    // ----------- MARKET STORAGE ------------
    /**
     * @inheritdoc ImToken
     */
    address public interestRateModel;

    /**
     * @inheritdoc ImToken
     */
    uint256 public reserveFactorMantissa;

    /**
     * @inheritdoc ImToken
     */
    uint256 public accrualBlockTimestamp;

    /**
     * @inheritdoc ImToken
     */
    uint256 public borrowIndex;

    /**
     * @inheritdoc ImToken
     */
    uint256 public totalBorrows;

    /**
     * @inheritdoc ImToken
     */
    uint256 public totalReserves;

    /**
     * @inheritdoc ImTokenMinimal
     */
    uint256 public totalSupply;

    /**
     * @inheritdoc ImTokenMinimal
     */
    uint256 public totalUnderlying;

    /**
     * @notice Maximum borrow rate that can ever be applied
     */
    uint256 public borrowRateMaxMantissa = 0.0005e16;

    /**
     * @inheritdoc ImToken
     */
    bool public sameChainFlowStateDisabled;

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    // Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    // Official record of token balances for each account
    mapping(address => uint256) internal accountTokens;

    // Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint256)) internal transferAllowances;

    /**
     * @notice Initial exchange rate used when minting the first mTokens (used when totalSupply = 0)
     */
    uint256 internal initialExchangeRateMantissa;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    uint256 internal constant RESERVE_FACTOR_MAX_MANTISSA = 1e18;

    /**
     * @notice Share of seized collateral that is added to reserves
     */
    uint256 internal constant PROTOCOL_SEIZE_SHARE_MANTISSA = 2.8e16; //2.8%

    // ----------- ERRORS ------------
    error mToken_OnlyAdmin();
    error mToken_RedeemEmpty();
    error mToken_InvalidInput();
    error mToken_OnlyAdminOrRole();
    error mToken_TransferNotValid();
    error mToken_MinAmountNotValid();
    error mToken_BorrowRateTooHigh();
    error mToken_AlreadyInitialized();
    error mToken_ReserveFactorTooHigh();
    error mToken_ExchangeRateNotValid();
    error mToken_MarketMethodNotValid();
    error mToken_LiquidateSeizeTooMuch();
    error mToken_RedeemCashNotAvailable();
    error mToken_BorrowCashNotAvailable();
    error mToken_ReserveCashNotAvailable();
    error mToken_RedeemTransferOutNotPossible();
    error mToken_SameChainOperationsAreDisabled();
    error mToken_CollateralBlockTimestampNotValid();

    // ----------- ACCESS EVENTS ------------
    /**
     * @notice Event emitted when rolesOperator is changed
     */
    event NewRolesOperator(address indexed oldRoles, address indexed newRoles);

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address indexed oldPendingAdmin, address indexed newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @notice Event emitted when Operator is changed
     */
    event NewOperator(address indexed oldOperator, address indexed newOperator);

    // ----------- TOKENS EVENTS ------------
    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // ----------- MARKETS EVENTS ------------
    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);

    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address indexed minter, address indexed receiver, uint256 mintAmount, uint256 mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address indexed redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address indexed borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(
        address indexed payer,
        address indexed borrower,
        uint256 repayAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(
        address indexed liquidator,
        address indexed borrower,
        uint256 repayAmount,
        address indexed mTokenCollateral,
        uint256 seizeTokens
    );

    /**
     * @notice Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(address indexed oldInterestRateModel, address indexed newInterestRateModel);

    /**
     * @notice Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address indexed benefactor, uint256 addAmount, uint256 newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address indexed admin, uint256 reduceAmount, uint256 newTotalReserves);

    /**
     * @notice Event emitted when the borrow max mantissa is updated
     */
    event NewBorrowRateMaxMantissa(uint256 oldVal, uint256 maxMantissa);

    /**
     * @notice Event emitted when same chain flow state is enabled or disabled
     */
    event SameChainFlowStateUpdated(address indexed sender, bool _oldState, bool _newState);

    /**
     * @notice Event emitted when same chain flow state is enabled or disabled
     */
    event ZkVerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // ----------- VIRTUAL ------------
    /**
     * @inheritdoc ImToken
     */
    function accrueInterest() external virtual {
        _accrueInterest();
    }

    /**
     * @dev Function to simply retrieve block timestamp
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function _getBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the MToken
     * @dev This function does not accrue interest before calculating the exchange rate
     *      Can generate issues if inflated by an attacker when market is created
     *      Solution: use 0 collateral factor initially
     * @return calculated exchange rate scaled by 1e18
     */
    function _exchangeRateStored() internal view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return initialExchangeRateMantissa;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint256 totalCash = _getCashPrior();
            uint256 cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;
            uint256 exchangeRate = (cashPlusBorrowsMinusReserves * expScale) / _totalSupply;

            return exchangeRate;
        }
    }

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying owned by this contract
     */
    function _getCashPrior() internal view virtual returns (uint256);

    /**
     * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
     *  This may revert due to insufficient balance or insufficient allowance.
     */
    function _doTransferIn(address from, uint256 amount) internal virtual returns (uint256);

    /**
     * @dev Performs a transfer out, ideally returning an explanatory error code upon failure rather than reverting.
     *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
     *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
     */
    function _doTransferOut(address payable to, uint256 amount) internal virtual;

    // ----------- NON-VIRTUAL ------------
    function _accrueInterest() internal {
        /* Remember the initial block timestamp */
        uint256 currentBlockTimestamp = _getBlockTimestamp();
        uint256 accrualBlockTimestampPrior = accrualBlockTimestamp;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockTimestampPrior == currentBlockTimestamp) return;

        /* Read the previous values out of storage */
        uint256 cashPrior = _getCashPrior();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        uint256 borrowRateMantissa =
            IInterestRateModel(interestRateModel).getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
        if (borrowRateMaxMantissa > 0) {
            require(borrowRateMantissa <= borrowRateMaxMantissa, mToken_BorrowRateTooHigh());
        }

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockTimestamp - accrualBlockTimestampPrior;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
        uint256 interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew =
            mul_ScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
        uint256 borrowIndexNew = mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockTimestamp = currentBlockTimestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);
    }
}
