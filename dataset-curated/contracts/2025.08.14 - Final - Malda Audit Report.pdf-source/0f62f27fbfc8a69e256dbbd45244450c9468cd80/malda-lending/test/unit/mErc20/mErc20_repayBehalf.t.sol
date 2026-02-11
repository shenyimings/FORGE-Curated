// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// interfaces
import {IRoles} from "src/interfaces/IRoles.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

// contracts
import {mTokenStorage} from "src/mToken/mTokenStorage.sol";
import {OperatorStorage} from "src/Operator/OperatorStorage.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mErc20_repay is mToken_Unit_Shared {
    function test_RevertGiven_MarketIsPausedForRepay(uint256 amount)
        external
        whenPaused(address(mWeth), ImTokenOperationTypes.OperationType.Repay)
        whenMarketIsListed(address(mWeth))
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWeth.repayBehalf(address(this), amount);
    }

    function test_RevertGiven_MarketIsNotListed(uint256 amount)
        external
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Repay)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWeth.repayBehalf(address(this), amount);
    }

    function test_GivenAmountIs0(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Repay)
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenMarketEntered(address(mWeth))
    {
        _repayPrerequisites(address(mWeth), amount * 2, amount);

        uint256 totalBorrowsBefore = mWeth.totalBorrows();

        _getTokens(weth, alice, amount);
        _resetContext(alice);
        weth.approve(address(mWeth), amount);
        mWeth.repayBehalf(address(this), 0);
        _resetContext(address(this));

        uint256 totalBorrowsAfter = mWeth.totalBorrows();

        // state should be the same
        assertEq(totalBorrowsAfter, totalBorrowsBefore);
    }

    modifier givenAmountIsGreaterThan0() {
        // does nothing; only for readability purposes
        _;
    }

    modifier whenStateIsValid() {
        // does nothing; only for readability purposes
        _;
    }

    struct RepayStateInternal {
        uint256 balanceUnderlyingBefore;
        uint256 balanceMTokenBefore;
        uint256 totalMSupplyBefore;
        uint256 totalBorrowsBefore;
        uint256 accountBorrowBefore;
        uint256 balanceUnderlyingAfter;
        uint256 balanceMTokenAfter;
        uint256 totalMSupplyAfter;
        uint256 totalBorrowsAfter;
        uint256 accountBorrowAfter;
    }

    function test_WhenRepayTooMuch(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenStateIsValid
        inRange(amount, SMALL, LARGE)
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Repay)
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenMarketEntered(address(mWeth))
    {
        {
            _repayPrerequisites(address(mWeth), amount * 2, amount);
            _getTokens(weth, address(this), amount * 10);
            weth.approve(address(mWeth), amount * 10);
        }

        _getTokens(weth, alice, amount);

        RepayStateInternal memory vars;
        // before state
        vars.balanceUnderlyingBefore = weth.balanceOf(alice);
        vars.balanceMTokenBefore = mWeth.balanceOf(address(this));
        vars.totalBorrowsBefore = mWeth.totalBorrows();
        vars.accountBorrowBefore = mWeth.borrowBalanceStored(address(this));

        vm.expectRevert(); //panic: arithmetic underflow or overflow (0x11)
        mWeth.repayBehalf(address(this), amount * 10);

        _resetContext(alice);
        weth.approve(address(mWeth), amount);
        mWeth.repayBehalf(address(this), type(uint256).max);
        _resetContext(address(this));

        // after state
        vars.balanceUnderlyingAfter = weth.balanceOf(alice);
        vars.balanceMTokenAfter = mWeth.balanceOf(address(this));
        vars.totalBorrowsAfter = mWeth.totalBorrows();
        vars.accountBorrowAfter = mWeth.borrowBalanceStored(address(this));

        {
            // it should use only the amount borrowed
            assertEq(vars.balanceUnderlyingBefore - vars.balanceUnderlyingAfter, amount);

            // it should have same mToken balance
            assertEq(vars.balanceMTokenBefore, vars.balanceMTokenAfter);

            // it should decrease totalBorrows
            assertGt(vars.totalBorrowsBefore, vars.totalBorrowsAfter);

            // it should decrease accountBorrows
            assertGt(vars.accountBorrowBefore, vars.accountBorrowAfter);
        }
    }

    function test_WhenRepayLessX(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenStateIsValid
        inRange(amount, SMALL, LARGE)
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Repay)
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenMarketEntered(address(mWeth))
    {
        RepayStateInternal memory vars;

        _repayPrerequisites(address(mWeth), amount * 2, amount);

        uint256 repayAmount = amount / 10;

        _getTokens(weth, alice, repayAmount);

        // before state
        vars.balanceUnderlyingBefore = weth.balanceOf(alice);
        vars.balanceMTokenBefore = mWeth.balanceOf(address(this));
        vars.totalMSupplyBefore = mWeth.totalSupply();
        vars.totalBorrowsBefore = mWeth.totalBorrows();
        vars.accountBorrowBefore = mWeth.borrowBalanceStored(address(this));

        _resetContext(alice);
        weth.approve(address(mWeth), repayAmount);
        mWeth.repayBehalf(address(this), repayAmount);
        _resetContext(address(this));

        // after state
        vars.balanceUnderlyingAfter = weth.balanceOf(alice);
        vars.balanceMTokenAfter = mWeth.balanceOf(address(this));
        vars.totalMSupplyAfter = mWeth.totalSupply();
        vars.totalBorrowsAfter = mWeth.totalBorrows();
        vars.accountBorrowAfter = mWeth.borrowBalanceStored(address(this));

        // it should use only the amount borrowed
        assertEq(vars.balanceUnderlyingBefore - vars.balanceUnderlyingAfter, repayAmount);

        // it should have same mToken balance
        assertEq(vars.balanceMTokenBefore, vars.balanceMTokenAfter);

        // it should decrease totalBorrows
        assertGt(vars.totalBorrowsBefore, vars.totalBorrowsAfter);
        assertGt(vars.totalBorrowsAfter, 0);

        // it should decrease accountBorrows
        assertGt(vars.accountBorrowBefore, vars.accountBorrowAfter);
        assertGt(vars.accountBorrowAfter, 0);
    }
}
