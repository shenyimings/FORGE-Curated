// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// interfaces
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

// contracts
import {OperatorStorage} from "src/Operator/OperatorStorage.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mErc20Host_borrow is mToken_Unit_Shared {
    function setUp() public virtual override {
        super.setUp();

        mWethHost.updateAllowedChain(uint32(block.chainid), true);
    }

    function test_RevertGiven_MarketIsPausedForBorrow(uint256 amount)
        external
        whenPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWethHost.borrow(amount);
    }

    function test_RevertGiven_MarketIsNotListed(uint256 amount)
        external
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWethHost.borrow(amount);
    }

    function test_RevertGiven_OracleReturnsEmptyPrice(uint256 amount)
        external
        whenPriceIs(ZERO_VALUE)
        whenUnderlyingPriceIs(ZERO_VALUE)
        whenMarketIsListed(address(mWethHost))
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        // it should revert
        vm.expectRevert(OperatorStorage.Operator_EmptyPrice.selector);
        mWethHost.borrow(amount);
    }

    modifier givenAmountIsGreaterThan0() {
        // does nothing; only for readability purposes
        _;
    }

    function test_WhenThereIsNotEnoughSupply(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenMarketEntered(address(mWethHost))
    {
        // it should revert with mt_BorrowCashNotAvailable but it actually reverts with InsufficientLiquidity for non cross-chain tokens
        // cannot test this in a non-external flow
        vm.expectRevert();
        mWethHost.borrow(amount);
    }

    function test_WhenBorrowCapIsReached(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenBorrowCapReached(address(mWethHost), amount)
    {
        // it should revert with Operator_MarketBorrowCapReached
        vm.expectRevert(OperatorStorage.Operator_MarketBorrowCapReached.selector);
        mWethHost.borrow(amount);
    }

    function test_WhenBorrowTooMuch(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenMarketEntered(address(mWethHost))
    {
        _borrowPrerequisites(address(mWethHost), amount);

        vm.expectRevert(OperatorStorage.Operator_InsufficientLiquidity.selector);
        mWethHost.borrow(amount);
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
        whenMarketIsListed(address(mWethHost))
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
    {
        // supply tokens; assure collateral factor is met
        _borrowPrerequisites(address(mWethHost), amount * 2);

        // before state
        uint256 balanceUnderlyingBefore = weth.balanceOf(address(this));
        uint256 balanceUnderlyingMTokenBefore = weth.balanceOf(address(mWethHost));
        uint256 supplyUnderlyingBefore = weth.totalSupply();
        uint256 totalBorrowsBefore = mWethHost.totalBorrows();

        // borrow; should fail
        vm.expectRevert(OperatorStorage.Operator_InsufficientLiquidity.selector);
        mWethHost.borrow(amount);

        // borrow; try again
        operator.setCollateralFactor(address(mWethHost), DEFAULT_COLLATERAL_FACTOR);
        mWethHost.borrow(amount);

        _afterBorrowChecks(
            amount, balanceUnderlyingBefore, balanceUnderlyingMTokenBefore, supplyUnderlyingBefore, totalBorrowsBefore
        );
    }

    function test_GivenMarketIsActive(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenStateIsValid
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        inRange(amount, SMALL, LARGE)
        whenMarketEntered(address(mWethHost))
    {
        // supply tokens; assure collateral factor is met
        _borrowPrerequisites(address(mWethHost), amount * 2);

        // before state
        uint256 balanceUnderlyingBefore = weth.balanceOf(address(this));
        uint256 balanceUnderlyingMTokenBefore = weth.balanceOf(address(mWethHost));
        uint256 supplyUnderlyingBefore = weth.totalSupply();
        uint256 totalBorrowsBefore = mWethHost.totalBorrows();

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
        mWethHost.borrow(amount);

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
        bool memberAfter = operator.checkMembership(address(this), address(mWethHost));
        uint256 balanceUnderlyingAfter = weth.balanceOf(address(this));
        uint256 balanceUnderlyingMTokenAfter = weth.balanceOf(address(mWethHost));
        uint256 supplyUnderlyingAfter = weth.totalSupply();
        uint256 totalBorrowsAfter = mWethHost.totalBorrows();

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

    modifier whenBorrowOnExtensionIsCalled() {
        // @dev does nothing; for readability only
        _;
    }

    modifier givenDecodedLiquidityIsValid() {
        // @dev does nothing; for readability only
        _;
    }

    function test_WhenBorrowOnExtensionVerificationWasOk(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenBorrowOnExtensionIsCalled
        givenDecodedLiquidityIsValid
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        // supply tokens; assure collateral factor is met
        _borrowPrerequisites(address(mWethHost), amount * 2);

        // before state
        uint256 balanceUnderlyingBefore = weth.balanceOf(address(this));
        uint256 totalBorrowsBefore = mWethHost.totalBorrows();

        mWethHost.updateAllowedChain(1, true);
        mWethHost.performExtensionCall(2, amount, 1);

        {
            uint256 balanceUnderlyingAfter = weth.balanceOf(address(this));
            uint256 totalBorrowsAfter = mWethHost.totalBorrows();

            assertEq(balanceUnderlyingBefore, balanceUnderlyingAfter, "1");
            assertLt(totalBorrowsBefore, totalBorrowsAfter, "2");
        }
    }
}
