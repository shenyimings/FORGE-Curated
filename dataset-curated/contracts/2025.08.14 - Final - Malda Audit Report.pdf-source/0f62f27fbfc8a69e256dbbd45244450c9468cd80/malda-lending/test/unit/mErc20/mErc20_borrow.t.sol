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

contract mErc20_borrow is mToken_Unit_Shared {
    function test_RevertGiven_MarketIsPausedForBorrow(uint256 amount)
        external
        whenPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWeth.borrow(amount);
    }

    function test_RevertGiven_MarketIsNotListed(uint256 amount)
        external
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWeth.borrow(amount);
    }

    function test_RevertGiven_OracleReturnsEmptyPrice(uint256 amount)
        external
        whenPriceIs(ZERO_VALUE)
        whenUnderlyingPriceIs(ZERO_VALUE)
        whenMarketIsListed(address(mWeth))
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        // it should revert
        vm.expectRevert(OperatorStorage.Operator_EmptyPrice.selector);
        mWeth.borrow(amount);
    }

    modifier givenAmountIsGreaterThan0() {
        // does nothing; only for readability purposes
        _;
    }

    function test_WhenThereIsNotEnoughSupply(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenMarketEntered(address(mWeth))
    {
        // it should revert with mToken_BorrowCashNotAvailable but it actually reverts with InsufficientLiquidity for non cross-chain tokens
        // cannot test this in a non-external flow
        vm.expectRevert();
        mWeth.borrow(amount);
    }

    function test_WhenBorrowCapIsReached(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenBorrowCapReached(address(mWeth), amount)
    {
        // it should revert with Operator_MarketBorrowCapReached
        vm.expectRevert(OperatorStorage.Operator_MarketBorrowCapReached.selector);
        mWeth.borrow(amount);
    }

    function test_WhenBorrowTooMuch(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenMarketEntered(address(mWeth))
    {
        _borrowPrerequisites(address(mWeth), amount);

        vm.expectRevert(OperatorStorage.Operator_InsufficientLiquidity.selector);
        mWeth.borrow(amount);
    }

    modifier whenStateIsValid() {
        // does nothing; only for readability purposes
        _;
    }

    function test_GivenMarketIsNotEntered(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenStateIsValid
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        // supply tokens; assure collateral factor is met
        _borrowPrerequisites(address(mWeth), amount * 2);

        // before state
        uint256 balanceUnderlyingBefore = weth.balanceOf(address(this));
        uint256 balanceUnderlyingMTokenBefore = weth.balanceOf(address(mWeth));
        uint256 supplyUnderlyingBefore = weth.totalSupply();
        uint256 totalBorrowsBefore = mWeth.totalBorrows();

        // borrow; should fail
        vm.expectRevert(OperatorStorage.Operator_InsufficientLiquidity.selector);
        mWeth.borrow(amount);

        // borrow; try again
        operator.setCollateralFactor(address(mWeth), DEFAULT_COLLATERAL_FACTOR);
        mWeth.borrow(amount);

        _afterBorrowChecks(
            amount, balanceUnderlyingBefore, balanceUnderlyingMTokenBefore, supplyUnderlyingBefore, totalBorrowsBefore
        );
    }

    function test_GivenMarketIsActive(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenStateIsValid
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWeth))
        whenNotPaused(address(mWeth), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenMarketEntered(address(mWeth))
    {
        // supply tokens; assure collateral factor is met
        _borrowPrerequisites(address(mWeth), amount * 2);

        // before state
        uint256 balanceUnderlyingBefore = weth.balanceOf(address(this));
        uint256 balanceUnderlyingMTokenBefore = weth.balanceOf(address(mWeth));
        uint256 supplyUnderlyingBefore = weth.totalSupply();
        uint256 totalBorrowsBefore = mWeth.totalBorrows();

        _borrowAndCheck(
            amount, balanceUnderlyingBefore, balanceUnderlyingMTokenBefore, supplyUnderlyingBefore, totalBorrowsBefore
        );
    }

    // stack too deep
    function _borrowAndCheck(
        uint256 amount,
        uint256 balanceUnderlyingBefore,
        uint256 balanceUnderlyingMTokenBefore,
        uint256 supplyUnderlyingBefore,
        uint256 totalBorrowsBefore
    ) private {
        // borrow
        mWeth.borrow(amount);

        _afterBorrowChecks(
            amount, balanceUnderlyingBefore, balanceUnderlyingMTokenBefore, supplyUnderlyingBefore, totalBorrowsBefore
        );
    }

    function _afterBorrowChecks(
        uint256 amount,
        uint256 balanceUnderlyingBefore,
        uint256 balanceUnderlyingMTokenBefore,
        uint256 supplyUnderlyingBefore,
        uint256 totalBorrowsBefore
    ) private view {
        // after state
        bool memberAfter = operator.checkMembership(address(this), address(mWeth));
        uint256 balanceUnderlyingAfter = weth.balanceOf(address(this));
        uint256 balanceUnderlyingMTokenAfter = weth.balanceOf(address(mWeth));
        uint256 supplyUnderlyingAfter = weth.totalSupply();
        uint256 totalBorrowsAfter = mWeth.totalBorrows();

        // it shoud activate ther market for sender
        assertTrue(memberAfter);

        // it should transfer underlying token to sender
        assertGt(balanceUnderlyingAfter, balanceUnderlyingBefore);
        assertEq(balanceUnderlyingAfter - amount, balanceUnderlyingBefore);

        // it should not modify underlying supply
        assertEq(supplyUnderlyingBefore, supplyUnderlyingAfter);

        // it should decrease balance of underlying from mToken
        assertGt(balanceUnderlyingMTokenBefore, balanceUnderlyingMTokenAfter);

        // it should increase totalBorrows
        assertGt(totalBorrowsAfter, totalBorrowsBefore);
    }
}
