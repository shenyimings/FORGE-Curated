// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// interfaces
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {IOperator} from "src/interfaces/IOperator.sol";

// contracts
import {OperatorStorage} from "src/Operator/OperatorStorage.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";
contract mErc20Host_liquidate is mToken_Unit_Shared {
    function setUp() public virtual override {
        super.setUp();

        mWethHost.updateAllowedChain(uint32(block.chainid), true);
    }

    function test_RevertGiven_MarketIsPausedForLiquidation(uint256 amount)
        external
        whenPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Liquidate)
        whenMarketIsListed(address(mWethHost))
        inRange(amount, SMALL, LARGE)
    {
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory users = new address[](1);
        users[0] = alice;
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWethHost.liquidateExternal(journalData, "0x123", users, amounts, collaterals, address(this));
    }

    modifier givenMarketIsNotPaused() {
        _;
    }

    function test_RevertWhen_JournalIsEmpty(uint256 amount)
        external
        givenMarketIsNotPaused
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory users = new address[](1);
        users[0] = alice;
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        vm.expectRevert(ImErc20Host.mErc20Host_JournalNotValid.selector);
        mWethHost.liquidateExternal("", "0x123", users, amounts, collaterals, address(this));
    }

    function test_RevertWhen_JournalIsNonEmptyButLengthIsNotValid(uint256 amount)
        external
        givenMarketIsNotPaused
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory users = new address[](1);
        users[0] = alice;
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        vm.expectRevert();
        mWethHost.liquidateExternal("0x", "0x123", users, amounts, collaterals, address(this));
    }

    function test_WhenDecodedAmountIs0() external givenMarketIsNotPaused {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        address[] memory users = new address[](1);
        users[0] = alice;
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), 0);

        (address(batchSubmitter));

        vm.expectRevert(ImErc20Host.mErc20Host_AmountNotValid.selector);
        mWethHost.liquidateExternal(journalData, "0x123", users, amounts, collaterals, address(this));
    }

    modifier whenDecodedAmountIsValid() {
        _;
    }

    function test_RevertWhen_SealVerificationFails(uint256 amount)
        external
        givenMarketIsNotPaused
        whenDecodedAmountIsValid
        inRange(amount, SMALL, LARGE)
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory users = new address[](1);
        users[0] = alice;
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        verifierMock.setStatus(true); // set for failure

        vm.expectRevert();
        mWethHost.liquidateExternal(journalData, "0x123", users, amounts, collaterals, address(this));
    }

    function test_RevertWhen_UserIsTheSameAsTheLiquidator(uint256 amount)
        external
        givenMarketIsNotPaused
        whenDecodedAmountIsValid
        inRange(amount, SMALL, LARGE)
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory users = new address[](1);
        users[0] = alice;
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        bytes memory journalData = _createAccumulatedAmountJournal(alice, address(mWethHost), amount);

        vm.expectRevert(ImErc20Host.mErc20Host_CallerNotAllowed.selector);
        mWethHost.liquidateExternal(journalData, "0x123", users, amounts, collaterals, address(this));
    }

    struct LiquidateStateInternal {
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

    function test_WhenSealVerificationWasOk_RepayTooMuch(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
        whenMarketIsListed(address(mWethHost))
        whenMarketEntered(address(mWethHost))
        givenMarketIsNotPaused
        whenDecodedAmountIsValid
    {
        mWethHost.setRolesOperator(address(roles));

        _repayPrerequisites(address(mWethHost), amount * 2, amount);

        _getTokens(weth, alice, amount * 10);
        bytes memory journalData = _createAccumulatedAmountJournal(bob, address(mWethHost), amount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount / 10;
        address[] memory users = new address[](1);
        users[0] = address(this);
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mWethHost);

        operator.setCloseFactor(0.086e18);
        operator.setLiquidationIncentive(address(mWethHost), 1e17);

        _resetContext(bob);
        mWethHost.updateAllowedCallerStatus(alice, true);

        _resetContext(alice);
        vm.expectRevert();
        mWethHost.liquidateExternal(journalData, "0x123", users, amounts, collaterals, address(this));
    }
}
