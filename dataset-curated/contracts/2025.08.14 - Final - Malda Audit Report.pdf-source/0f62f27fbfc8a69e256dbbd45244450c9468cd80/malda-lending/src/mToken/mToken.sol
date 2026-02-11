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
import {IOperator, IOperatorDefender} from "src/interfaces/IOperator.sol";

// contracts
import {mTokenConfiguration} from "./mTokenConfiguration.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract mToken is mTokenConfiguration, ReentrancyGuard {

    constructor() {
        borrowRateMaxMantissa = 0.0005e16;
    }
    /**
     * @notice Initialize the money market
     * @param operator_ The address of the Operator
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ EIP-20 name of this token
     * @param symbol_ EIP-20 symbol of this token
     * @param decimals_ EIP-20 decimal precision of this token
     */
    function _initializeMToken(
        address operator_,
        address interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal {
        require(accrualBlockTimestamp == 0 && borrowIndex == 0, mToken_AlreadyInitialized());
        require(initialExchangeRateMantissa_ > 0, mToken_ExchangeRateNotValid());
        // Set initial exchange rate
        initialExchangeRateMantissa = initialExchangeRateMantissa_;

        _setOperator(operator_);

        accrualBlockTimestamp = _getBlockTimestamp();
        borrowIndex = mantissaOne;

        _setInterestRateModel(interestRateModel_);

        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function isMToken() external pure override returns (bool) {
        return true;
    }

    // ----------- TOKENS VIEW ------------
    /**
     * @inheritdoc ImToken
     */
    function allowance(address owner, address spender) external view override returns (uint256) {
        return transferAllowances[owner][spender];
    }

    /**
     * @inheritdoc ImTokenMinimal
     */
    function balanceOf(address owner) external view override returns (uint256) {
        return accountTokens[owner];
    }

    /**
     * @inheritdoc ImToken
     */
    function balanceOfUnderlying(address owner) external override returns (uint256) {
        Exp memory exchangeRate = Exp({mantissa: exchangeRateCurrent()});
        return mul_ScalarTruncate(exchangeRate, accountTokens[owner]);
    }

    // ----------- MARKETS VIEW ------------
    /**
     * @inheritdoc ImToken
     */
    function getAccountSnapshot(address account) external view override returns (uint256, uint256, uint256) {
        return (accountTokens[account], _borrowBalanceStored(account), _exchangeRateStored());
    }

    /**
     * @inheritdoc ImToken
     */
    function borrowRatePerBlock() external view override returns (uint256) {
        return IInterestRateModel(interestRateModel).getBorrowRate(_getCashPrior(), totalBorrows, totalReserves);
    }

    /**
     * @inheritdoc ImToken
     */
    function supplyRatePerBlock() external view override returns (uint256) {
        return IInterestRateModel(interestRateModel).getSupplyRate(
            _getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa
        );
    }

    /**
     * @inheritdoc ImToken
     */
    function borrowBalanceStored(address account) external view override returns (uint256) {
        return _borrowBalanceStored(account);
    }

    /**
     * @inheritdoc ImToken
     */
    function getCash() external view override returns (uint256) {
        return _getCashPrior();
    }

    /**
     * @inheritdoc ImToken
     */
    function exchangeRateStored() external view override returns (uint256) {
        return _exchangeRateStored();
    }

    // ----------- TOKENS PUBLIC ------------
    /**
     * @inheritdoc ImToken
     */
    function transfer(address dst, uint256 amount) external override nonReentrant returns (bool) {
        _transferTokens(msg.sender, msg.sender, dst, amount);

        return true;
    }

    /**
     * @inheritdoc ImToken
     */
    function transferFrom(address src, address dst, uint256 amount) external override nonReentrant returns (bool) {
        _transferTokens(msg.sender, src, dst, amount);

        return true;
    }

    /**
     * @inheritdoc ImToken
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        address src = msg.sender;
        transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    // ----------- MARKETS PUBLIC ------------
    /**
     * @inheritdoc ImToken
     */
    function totalBorrowsCurrent() external override nonReentrant returns (uint256) {
        _accrueInterest();
        return totalBorrows;
    }

    /**
     * @inheritdoc ImToken
     */
    function borrowBalanceCurrent(address account) external override nonReentrant returns (uint256) {
        _accrueInterest();
        return _borrowBalanceStored(account);
    }

    /**
     * @inheritdoc ImToken
     */
    function exchangeRateCurrent() public override nonReentrant returns (uint256) {
        _accrueInterest();
        return _exchangeRateStored();
    }

    /**
     * @inheritdoc ImToken
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens) external override nonReentrant {
        _seize(msg.sender, liquidator, borrower, seizeTokens);
    }

    /**
     * @inheritdoc ImToken
     */
    function reduceReserves(uint256 reduceAmount) external override nonReentrant {
        require(
            msg.sender == admin || rolesOperator.isAllowedFor(msg.sender, rolesOperator.GUARDIAN_RESERVE()),
            mToken_OnlyAdminOrRole()
        );

        _accrueInterest();

        require(_getCashPrior() >= reduceAmount, mToken_ReserveCashNotAvailable());
        require(reduceAmount <= totalReserves, mToken_ReserveCashNotAvailable());

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        // totalReserves - reduceAmount
        uint256 totalReservesNew = totalReserves - reduceAmount;

        // Store reserves[n+1] = reserves[n] - reduceAmount
        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        _doTransferOut(payable(msg.sender), reduceAmount);
        totalUnderlying -= reduceAmount;

        emit ReservesReduced(admin, reduceAmount, totalReservesNew);
    }

    // ----------- INTERNAL VIEW ------------
    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return (error code, the calculated balance or 0 if error code is non-zero)
     */
    function _borrowBalanceStored(address account) internal view returns (uint256) {
        /* Get borrowBalance and borrowIndex */
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        uint256 principalTimesIndex = borrowSnapshot.principal * borrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    // ----------- INTERNAL ------------
    /**
     * @notice Sender supplies assets into the market and receives mTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param user The user address
     * @param user The receiver address
     * @param mintAmount The amount of the underlying asset to supply
     * @param minAmountOut The minimum amount to be received
     * @param doTransfer If an actual transfer should be performed
     */
    function _mint(address user, address receiver, uint256 mintAmount, uint256 minAmountOut, bool doTransfer)
        internal
        nonReentrant
    {
        _accrueInterest();
        // emits the actual Mint event if successful and logs on errors, so we don't need to
        __mint(user, receiver, mintAmount, minAmountOut, doTransfer);
    }

    /**
     * @notice Sender redeems mTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param user The user address
     * @param redeemTokens The number of mTokens to redeem into underlying
     * @param doTransfer If an actual transfer should be performed
     */
    function _redeem(address user, uint256 redeemTokens, bool doTransfer)
        internal
        nonReentrant
        returns (uint256 underlyingAmount)
    {
        _accrueInterest();
        // emits redeem-specific logs on errors, so we don't need to
        underlyingAmount = __redeem(payable(user), redeemTokens, 0, doTransfer);
    }

    /**
     * @notice Sender redeems mTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param user The user address
     * @param redeemAmount The amount of underlying to receive from redeeming mTokens
     * @param doTransfer If an actual transfer should be performed
     */
    function _redeemUnderlying(address user, uint256 redeemAmount, bool doTransfer) internal nonReentrant {
        _accrueInterest();
        // emits redeem-specific logs on errors, so we don't need to
        __redeem(payable(user), 0, redeemAmount, doTransfer);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param user The user address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @param doTransfer If an actual transfer should be performed
     */
    function _borrow(address user, uint256 borrowAmount, bool doTransfer) internal nonReentrant {
        _accrueInterest();
        // emits borrow-specific logs on errors, so we don't need to
        __borrow(payable(user), payable(user), borrowAmount, doTransfer);
    }

        /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param user The user address
     * @param receiver The underlying receiver address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function _borrowWithReceiver(address user, address receiver, uint256 borrowAmount) internal nonReentrant {
        _accrueInterest();
        __borrow(payable(user), payable(receiver), borrowAmount, true);
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or `type(uint256).max` for the full outstanding amount
     * @param doTransfer If an actual transfer should be performed
     */
    function _repay(uint256 repayAmount, bool doTransfer) internal nonReentrant returns (uint256) {
        _accrueInterest();
        // emits repay-borrow-specific logs on errors, so we don't need to
        return __repay(msg.sender, msg.sender, repayAmount, doTransfer);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or `type(uint256).max` for the full outstanding amount
     * @param doTransfer If an actual transfer should be performed
     */
    function _repayBehalf(address borrower, uint256 repayAmount, bool doTransfer)
        internal
        nonReentrant
        returns (uint256)
    {
        _accrueInterest();
        // emits repay-borrow-specific logs on errors, so we don't need to
        return __repay(msg.sender, borrower, repayAmount, doTransfer);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param liquidator The liquidator address
     * @param borrower The borrower of this mToken to be liquidated
     * @param mTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param doTransfer If an actual transfer should be performed
     */
    function _liquidate(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address mTokenCollateral,
        bool doTransfer
    ) internal nonReentrant {
        _accrueInterest();

        ImToken(mTokenCollateral).accrueInterest();

        // emits borrow-specific logs on errors, so we don't need to
        __liquidate(liquidator, borrower, repayAmount, mTokenCollateral, doTransfer);
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another mToken.
     *  Its absolutely critical to use msg.sender as the seizer mToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed mToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of mTokens to seize
     */
    function _seize(address seizerToken, address liquidator, address borrower, uint256 seizeTokens) internal {
        IOperatorDefender(operator).beforeMTokenSeize(address(this), seizerToken, liquidator, borrower);

        require(borrower != liquidator, mToken_InvalidInput());

        /*
         * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
         *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
         *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
         */
        uint256 protocolSeizeTokens = mul_(seizeTokens, Exp({mantissa: PROTOCOL_SEIZE_SHARE_MANTISSA}));
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;
        Exp memory exchangeRate = Exp({mantissa: _exchangeRateStored()});
        uint256 protocolSeizeAmount = mul_ScalarTruncate(exchangeRate, protocolSeizeTokens);
        uint256 totalReservesNew = totalReserves + protocolSeizeAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the calculated values into storage */
        totalReserves = totalReservesNew;
        totalSupply = totalSupply - protocolSeizeTokens;
        accountTokens[borrower] = accountTokens[borrower] - seizeTokens;
        accountTokens[liquidator] = accountTokens[liquidator] + liquidatorSeizeTokens;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(address(this), protocolSeizeAmount, totalReservesNew);
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring from msg.sender
     * @param addAmount Amount of addition to reserves
     */
    function _addReserves(uint256 addAmount) internal nonReentrant {
        _accrueInterest();

        // totalReserves + actualAddAmount
        uint256 totalReservesNew;
        uint256 actualAddAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the caller and the addAmount
         *  Note: The mToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the mToken holds an additional addAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  it returns the amount actually transferred, in case of a fee.
         */

        actualAddAmount = _doTransferIn(msg.sender, addAmount);
        totalUnderlying += actualAddAmount;

        totalReservesNew = totalReserves + actualAddAmount;

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        totalReserves = totalReservesNew;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);
    }

    // ----------- PRIVATE ------------
    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param borrower The borrower of this mToken to be liquidated
     * @param mTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param doTransfer If an actual transfer should be performed
     */
    function __liquidate(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address mTokenCollateral,
        bool doTransfer
    ) internal {
        require(borrower != liquidator, mToken_InvalidInput());
        require(repayAmount > 0 && repayAmount != type(uint256).max, mToken_InvalidInput());

        IOperatorDefender(operator).beforeMTokenLiquidate(address(this), mTokenCollateral, borrower, repayAmount);

        require(
            ImToken(mTokenCollateral).accrualBlockTimestamp() == _getBlockTimestamp(),
            mToken_CollateralBlockTimestampNotValid()
        );

        /* Fail if repayBorrow fails */
        uint256 actualRepayAmount = __repay(liquidator, borrower, repayAmount, doTransfer);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We calculate the number of collateral tokens that will be seized */
        uint256 seizeTokens =
            IOperator(operator).liquidateCalculateSeizeTokens(address(this), mTokenCollateral, actualRepayAmount);

        /* Revert if borrower collateral token balance < seizeTokens */
        require(ImToken(mTokenCollateral).balanceOf(borrower) >= seizeTokens, mToken_LiquidateSeizeTooMuch());

        // If this is also the collateral, run _seize to avoid re-entrancy, otherwise make an external call
        if (address(mTokenCollateral) == address(this)) {
            _seize(address(this), liquidator, borrower, seizeTokens);
        } else {
            ImToken(mTokenCollateral).seize(liquidator, borrower, seizeTokens);
        }

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(liquidator, borrower, actualRepayAmount, address(mTokenCollateral), seizeTokens);
    }
    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of underlying tokens being returned, or `type(uint256).max` for the full outstanding amount
     * @param doTransfer If an actual transfer should be performed
     */

    function __repay(address payer, address borrower, uint256 repayAmount, bool doTransfer) private returns (uint256) {
        IOperatorDefender(operator).beforeMTokenRepay(address(this), borrower);

        /* We fetch the amount the borrower owes, with accumulated interest */
        uint256 accountBorrowsPrev = _borrowBalanceStored(borrower);

        /* If repayAmount == type(uint256).max , repayAmount = accountBorrows */
        uint256 repayAmountFinal = repayAmount == type(uint256).max ? accountBorrowsPrev : repayAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call _doTransferIn for the payer and the repayAmount
         *  Note: The mToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the mToken holds an additional repayAmount of cash.
         *  _doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        uint256 actualRepayAmount = doTransfer ? _doTransferIn(payer, repayAmountFinal) : repayAmountFinal;
        totalUnderlying += actualRepayAmount;

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        uint256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
        uint256 totalBorrowsNew = totalBorrows - actualRepayAmount;

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(payer, borrower, actualRepayAmount, accountBorrowsNew, totalBorrowsNew);

        return actualRepayAmount;
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function __borrow(address payable borrower, address payable receiver, uint256 borrowAmount, bool doTransfer) private {
        IOperatorDefender(operator).beforeMTokenBorrow(address(this), borrower, borrowAmount);

        require(_getCashPrior() >= borrowAmount, mToken_BorrowCashNotAvailable());

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowNew = accountBorrow + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        uint256 accountBorrowsPrev = _borrowBalanceStored(borrower);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = totalBorrows + borrowAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing increased borrow before external transfer.
        `*/
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        if (doTransfer) {
            /*
            * We invoke _doTransferOut for the borrower and the borrowAmount.
            *  Note: The mToken must handle variations between ERC-20 and ETH underlying.
            *  On success, the mToken borrowAmount less of cash.
            *  _doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
            */
            _doTransferOut(receiver, borrowAmount);
        }
        totalUnderlying -= borrowAmount;

        /* We emit a Borrow event */
        emit Borrow(borrower, borrowAmount, accountBorrowsNew, totalBorrowsNew);
    }

    function __redeem(address payable redeemer, uint256 redeemTokensIn, uint256 redeemAmountIn, bool doTransfer)
        private
        returns (uint256 redeemAmount)
    {
        require(redeemTokensIn == 0 || redeemAmountIn == 0, mToken_InvalidInput());

        /* exchangeRate = invoke Exchange Rate Stored() */
        Exp memory exchangeRate = Exp({mantissa: _exchangeRateStored()});

        uint256 redeemTokens;
        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            redeemTokens = redeemTokensIn;
            redeemAmount = mul_ScalarTruncate(exchangeRate, redeemTokensIn);
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */
            redeemTokens = div_(redeemAmountIn, exchangeRate);
            redeemAmount = redeemAmountIn;
        }
        if (redeemTokens == 0 && redeemAmount == 0) revert mToken_RedeemEmpty();

        /* Fail if redeem not allowed */
        IOperatorDefender(operator).beforeMTokenRedeem(address(this), redeemer, redeemTokens);

        require(_getCashPrior() >= redeemAmount, mToken_RedeemCashNotAvailable());

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
         */
        totalSupply = totalSupply - redeemTokens;
        accountTokens[redeemer] = accountTokens[redeemer] - redeemTokens;

        /*
         * We invoke _doTransferOut for the redeemer and the redeemAmount.
         *  Note: The mToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the mToken has redeemAmount less of cash.
         *  _doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        if (doTransfer) _doTransferOut(redeemer, redeemAmount);
        totalUnderlying -= redeemAmount;

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), redeemTokens);
        emit Redeem(redeemer, redeemAmount, redeemTokens);
    }
    /**
     * @notice User supplies assets into the market and receives mTokens in exchange
     * @dev Assumes interest has already been accrued up to the current block
     * @param minter The address of the account which is supplying the assets
     * @param receiver The address of the account which is receiving the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @param minAmountOut The min amount to be received
     * @param doTransfer If an actual transfer should be performed
     */

    function __mint(address minter, address receiver, uint256 mintAmount, uint256 minAmountOut, bool doTransfer)
        private
    {
        IOperatorDefender(operator).beforeMTokenMint(address(this), minter);

        Exp memory exchangeRate = Exp({mantissa: _exchangeRateStored()});

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call `_doTransferIn` for the minter and the mintAmount.
         *  Note: The mToken must handle variations between ERC-20 and ETH underlying.
         *  `_doTransferIn` reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the mToken holds an additional `actualMintAmount`
         *  of cash.
         */
        uint256 actualMintAmount = doTransfer ? _doTransferIn(minter, mintAmount) : mintAmount;
        totalUnderlying += actualMintAmount;

        /*
         * We get the current exchange rate and calculate the number of mTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */

        uint256 mintTokens = div_(actualMintAmount, exchangeRate);
        require(mintTokens >= minAmountOut, mToken_MinAmountNotValid());

        // avoid exchangeRate manipulation
        if (totalSupply == 0) {
            totalSupply = 1000;
            accountTokens[address(0)] = 1000;
            mintTokens -= 1000;
        }

        /*
         * We calculate the new total supply of mTokens and minter token balance, checking for overflow:
         *  totalSupplyNew = totalSupply + mintTokens
         *  accountTokensNew = accountTokens[minter] + mintTokens
         * And write them into storage
         */
        totalSupply = totalSupply + mintTokens;
        accountTokens[receiver] = accountTokens[receiver] + mintTokens;

        /* We emit a Mint event, and a Transfer event */
        emit Mint(minter, receiver, actualMintAmount, mintTokens);
        emit Transfer(address(this), receiver, mintTokens);

        /* We call the defense hook */
        IOperatorDefender(operator).afterMTokenMint(address(this));

        // Activate market by default if not entered already
        bool isEntered = IOperator(operator).checkMembership(minter, address(this));
        if (!isEntered) {
            IOperator(operator).enterMarketsWithSender(minter);
        }
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     */
    function _transferTokens(address spender, address src, address dst, uint256 tokens) private {
        IOperatorDefender(operator).beforeMTokenTransfer(address(this), src, dst, tokens);

        require(src != dst, mToken_TransferNotValid());

        /* Get the allowance, infinite for the account owner */
        uint256 startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        uint256 allowanceNew = startingAllowance - tokens;
        uint256 srcTokensNew = accountTokens[src] - tokens;
        uint256 dstTokensNew = accountTokens[dst] + tokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        accountTokens[src] = srcTokensNew;
        accountTokens[dst] = dstTokensNew;

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != type(uint256).max) {
            transferAllowances[src][spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);
    }
}
