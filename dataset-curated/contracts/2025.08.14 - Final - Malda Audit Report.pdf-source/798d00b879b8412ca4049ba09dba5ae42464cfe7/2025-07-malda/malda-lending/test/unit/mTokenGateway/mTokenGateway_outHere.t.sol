// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {ImTokenGateway} from "src/interfaces/ImTokenGateway.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mTokenGateway_outHere is mToken_Unit_Shared {
    function setUp() public virtual override {
        super.setUp();

        vm.chainId(LINEA_CHAIN_ID);
    }

    function test_RevertGiven_IsPaused(uint256 amount) external inRange(amount, SMALL, LARGE) {
        ImTokenGateway(address(mWethExtension)).setPaused(ImTokenOperationTypes.OperationType.AmountOutHere, true);

        vm.expectRevert();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        mWethExtension.outHere("", "0x123", amounts, address(this));
    }

    modifier givenMarketIsNotPaused() {
        _;
    }

    function test_RevertWhen_AmountIs(uint256 amount) external inRange(amount, SMALL, LARGE) givenMarketIsNotPaused {
        // it should revert
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethExtension), amount);

        vm.expectRevert(ImTokenGateway.mTokenGateway_AmountNotValid.selector);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        mWethExtension.outHere(journalData, "0x123", amounts, address(this));
    }

    function test_WhenAccumulatedAmountReceivedOrLessThanNeeded(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        givenMarketIsNotPaused
    {
        // it should revert with mTokenGateway_AmountTooBig
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethExtension), amount - 1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.expectRevert(ImTokenGateway.mTokenGateway_AmountTooBig.selector);
        mWethExtension.outHere(journalData, "0x123", amounts, address(this));
    }

    function test_WhenMarketDoesNotHaveLiquidity(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        givenMarketIsNotPaused
    {
        // it should revert with mTokenGateway_ReleaseCashNotAvailable
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethExtension), amount);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.expectRevert(ImTokenGateway.mTokenGateway_ReleaseCashNotAvailable.selector);
        mWethExtension.outHere(journalData, "0x123", amounts, address(this));
    }

    function test_RevertWhen_CallerNotAllowedXQ(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        givenMarketIsNotPaused
    {
        // it should revert
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethExtension), amount);
        _resetContext(alice);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.expectRevert(ImTokenGateway.mTokenGateway_CallerNotAllowed.selector);
        mWethExtension.outHere(journalData, "0x123", amounts, address(this));
    }

    function test_WhenParametersAreRight(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        givenMarketIsNotPaused
    {
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethExtension), amount);

        _getTokens(weth, address(mWethExtension), amount);

        uint256 balanceUserBefore = weth.balanceOf(address(this));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        mWethExtension.outHere(journalData, "0x123", amounts, address(this));
        uint256 balanceUserAfter = weth.balanceOf(address(this));

        // it should increase accAmountOut
        assertEq(mWethExtension.accAmountOut(address(this)), amount);

        // it should transfer underlying to user
        assertEq(balanceUserBefore + amount, balanceUserAfter);
    }

    function test_WhenParametersAreRightDifferentUsersQE(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        givenMarketIsNotPaused
    {
        vm.chainId(LINEA_CHAIN_ID);
        address[] memory allowerdCallers = new address[](1);
        allowerdCallers[0] = alice;
        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethExtension), amount);

        _getTokens(weth, address(mWethExtension), amount);

        uint256 balanceUserBefore = weth.balanceOf(address(this));
        mWethExtension.updateAllowedCallerStatus(alice, true);
        _resetContext(alice);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        mWethExtension.outHere(journalData, "0x123", amounts, address(this));
        uint256 balanceUserAfter = weth.balanceOf(address(this));

        // it should increase accAmountOut
        assertEq(mWethExtension.accAmountOut(address(this)), amount);

        // it should transfer underlying to user
        assertEq(balanceUserBefore + amount, balanceUserAfter);
    }
}
