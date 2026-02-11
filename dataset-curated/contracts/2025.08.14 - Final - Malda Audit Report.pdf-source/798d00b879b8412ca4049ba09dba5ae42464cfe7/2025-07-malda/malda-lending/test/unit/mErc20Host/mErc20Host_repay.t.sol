// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// interfaces
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

// contracts
import {OperatorStorage} from "src/Operator/OperatorStorage.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mErc20Host_repay is mToken_Unit_Shared {
    function setUp() public virtual override {
        super.setUp();

        mWethHost.updateAllowedChain(uint32(block.chainid), true);
    }

    function test_RevertGiven_MarketIsPausedForRepay(uint256 amount)
        external
        whenPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay)
        whenMarketIsListed(address(mWethHost))
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWethHost.repay(amount);
    }

    function test_RevertGiven_MarketIsNotListed(uint256 amount)
        external
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWethHost.repay(amount);
    }

    function test_GivenAmountIs0(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay)
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        _repayPrerequisites(address(mWethHost), amount * 2, amount);

        uint256 totalBorrowsBefore = mWethHost.totalBorrows();

        weth.approve(address(mWethHost), amount);
        mWethHost.repay(0);

        uint256 totalBorrowsAfter = mWethHost.totalBorrows();

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
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay)
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        {
            _repayPrerequisites(address(mWethHost), amount * 2, amount);
            _getTokens(weth, address(this), amount * 10);
            weth.approve(address(mWethHost), amount * 10);
        }

        RepayStateInternal memory vars;
        // before state
        vars.balanceUnderlyingBefore = weth.balanceOf(address(this));
        vars.balanceMTokenBefore = mWethHost.balanceOf(address(this));
        vars.totalBorrowsBefore = mWethHost.totalBorrows();
        vars.accountBorrowBefore = mWethHost.borrowBalanceStored(address(this));

        vm.expectRevert(); //panic: arithmetic underflow or overflow (0x11)
        mWethHost.repay(amount * 10);

        mWethHost.repay(type(uint256).max);

        // after state
        vars.balanceUnderlyingAfter = weth.balanceOf(address(this));
        vars.balanceMTokenAfter = mWethHost.balanceOf(address(this));
        vars.totalBorrowsAfter = mWethHost.totalBorrows();
        vars.accountBorrowAfter = mWethHost.borrowBalanceStored(address(this));

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

    function test_WhenRepayLess(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenStateIsValid
        inRange(amount, SMALL, LARGE)
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay)
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        RepayStateInternal memory vars;

        _repayPrerequisites(address(mWethHost), amount * 2, amount);

        uint256 repayAmount = amount / 10;
        weth.approve(address(mWethHost), repayAmount);

        // before state
        vars.balanceUnderlyingBefore = weth.balanceOf(address(this));
        vars.balanceMTokenBefore = mWethHost.balanceOf(address(this));
        vars.totalMSupplyBefore = mWethHost.totalSupply();
        vars.totalBorrowsBefore = mWethHost.totalBorrows();
        vars.accountBorrowBefore = mWethHost.borrowBalanceStored(address(this));

        mWethHost.repay(repayAmount);

        // after state
        vars.balanceUnderlyingAfter = weth.balanceOf(address(this));
        vars.balanceMTokenAfter = mWethHost.balanceOf(address(this));
        vars.totalMSupplyAfter = mWethHost.totalSupply();
        vars.totalBorrowsAfter = mWethHost.totalBorrows();
        vars.accountBorrowAfter = mWethHost.borrowBalanceStored(address(this));

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

    modifier whenRepayExternalIsCalled() {
        // @dev does nothing; for readability only
        _;
    }

    modifier givenDecodedAmountIsValid() {
        // @dev does nothing; for readability only
        _;
    }

    function test_RevertGiven_JournalIsEmpty(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenRepayExternalIsCalled
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectRevert(ImErc20Host.mErc20Host_JournalNotValid.selector);
        mWethHost.repayExternal("", "0x123", amounts, address(this));
    }

    function test_RevertGiven_JournalIsNonEmptyButLengthIsNotValid(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenRepayExternalIsCalled
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectRevert(ImErc20Host.mErc20Host_JournalNotValid.selector);
        mWethHost.repayExternal("", "0x123", amounts, address(this));
    }

    function test_GivenDecodedAmountIs0()
        external
        whenRepayExternalIsCalled
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenRepayExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), 0);

        vm.expectRevert(ImErc20Host.mErc20Host_AmountNotValid.selector);
        mWethHost.repayExternal(journalData, "0x123", amounts, address(this));
    }

    function test_RevertWhen_SealVerificationFails(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenRepayExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        verifierMock.setStatus(true); // set for failure

        vm.expectRevert();
        mWethHost.repayExternal(journalData, "0x123", amounts, address(this));
    }

    function test_WhenSealVerificationWasOk(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenRepayExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        RepayStateInternal memory vars;

        _repayPrerequisites(address(mWethHost), amount * 2, amount);

        // before state
        vars.balanceUnderlyingBefore = weth.balanceOf(address(this));
        vars.balanceMTokenBefore = mWethHost.balanceOf(address(this));
        vars.totalBorrowsBefore = mWethHost.totalBorrows();
        vars.accountBorrowBefore = mWethHost.borrowBalanceStored(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        mWethHost.repayExternal(journalData, "0x123", amounts, address(this));

        // after state
        vars.balanceUnderlyingAfter = weth.balanceOf(address(this));
        vars.balanceMTokenAfter = mWethHost.balanceOf(address(this));
        vars.totalBorrowsAfter = mWethHost.totalBorrows();
        vars.accountBorrowAfter = mWethHost.borrowBalanceStored(address(this));

        // it should not use tokens
        assertEq(vars.balanceUnderlyingBefore, vars.balanceUnderlyingAfter);

        // it should have same mToken balance
        assertEq(vars.balanceMTokenBefore, vars.balanceMTokenAfter);

        // it should decrease totalBorrows
        assertGt(vars.totalBorrowsBefore, vars.totalBorrowsAfter);
        assertEq(vars.totalBorrowsAfter, 0);

        // it should decrease accountBorrows
        assertGt(vars.accountBorrowBefore, vars.accountBorrowAfter);
        assertEq(vars.accountBorrowAfter, 0);
    }

    function test_WhenSealVerificationWasOk_AndRepayingMax(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenRepayExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
    {
        RepayStateInternal memory vars;

        _repayPrerequisites(address(mWethHost), amount * 2, amount);

        // before state
        vars.balanceUnderlyingBefore = weth.balanceOf(address(this));
        vars.balanceMTokenBefore = mWethHost.balanceOf(address(this));
        vars.totalBorrowsBefore = mWethHost.totalBorrows();
        vars.accountBorrowBefore = mWethHost.borrowBalanceStored(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = type(uint256).max;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        mWethHost.repayExternal(journalData, "0x123", amounts, address(this));

        // after state
        vars.balanceUnderlyingAfter = weth.balanceOf(address(this));
        vars.balanceMTokenAfter = mWethHost.balanceOf(address(this));
        vars.totalBorrowsAfter = mWethHost.totalBorrows();
        vars.accountBorrowAfter = mWethHost.borrowBalanceStored(address(this));

        // it should not use tokens
        assertEq(vars.balanceUnderlyingBefore, vars.balanceUnderlyingAfter);

        // it should have same mToken balance
        assertEq(vars.balanceMTokenBefore, vars.balanceMTokenAfter);

        // it should decrease totalBorrows
        assertGt(vars.totalBorrowsBefore, vars.totalBorrowsAfter);
        assertEq(vars.totalBorrowsAfter, 0);

        // it should decrease accountBorrows
        assertGt(vars.accountBorrowBefore, vars.accountBorrowAfter);
        assertEq(vars.accountBorrowAfter, 0);
    }
}
