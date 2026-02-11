// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// interfaces
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

// contracts
import {mTokenStorage} from "src/mToken/mTokenStorage.sol";
import {OperatorStorage} from "src/Operator/OperatorStorage.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mErc20Host_redeem is mToken_Unit_Shared {
    function setUp() public virtual override {
        super.setUp();

        mWethHost.updateAllowedChain(uint32(block.chainid), true);
    }

    function test_RevertGiven_MarketIsPausedForRdeem(uint256 amount)
        external
        whenPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        whenMarketIsListed(address(mWethHost))
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWethHost.redeem(amount);

        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWethHost.redeemUnderlying(amount);
    }

    function test_GivenMarketIsNotListed(uint256 amount)
        external
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWethHost.redeem(amount);

        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWethHost.redeemUnderlying(amount);
    }

    function test_GivenRedeemerIsNotPartOfTheMarket(uint256 amount)
        external
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
    {
        _getTokens(weth, address(mWethHost), amount);
        vm.expectRevert();
        mWethHost.redeem(amount);

        vm.expectRevert();
        mWethHost.redeemUnderlying(amount);
    }

    function test_GivenRedeemAmountsAre0()
        external
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        whenMarketIsListed(address(mWethHost))
    {
        vm.expectRevert(mTokenStorage.mToken_RedeemEmpty.selector);
        mWethHost.redeem(0);
        vm.expectRevert(mTokenStorage.mToken_RedeemEmpty.selector);
        mWethHost.redeemUnderlying(0);
    }

    modifier givenAmountIsGreaterThan0() {
        // does nothing; only for readability purposes
        _;
    }

    function test_WhenTheMarketDoesNotHaveEnoughAssetsForTheRedeemOperation(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
    {
        // it should revert with mToken_RedeemCashNotAvailable
        vm.expectRevert(mTokenStorage.mToken_RedeemCashNotAvailable.selector);
        mWethHost.redeem(amount);

        vm.expectRevert(mTokenStorage.mToken_RedeemCashNotAvailable.selector);
        mWethHost.redeemUnderlying(amount);
    }

    function test_WhenStateIsValidForRedeem(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
    {
        _redeem(amount, false);
    }

    function test_WhenStateIsValidForRedeemUnderlying(uint256 amount)
        external
        givenAmountIsGreaterThan0
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem)
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
    {
        _redeem(amount, true);
    }

    function _redeem(uint256 amount, bool underlying) private {
        _borrowPrerequisites(address(mWethHost), amount);

        uint256 balanceWethBefore = weth.balanceOf(address(this));
        uint256 supplyMTokenBefore = mWethHost.totalSupply();
        uint256 balanceMTokenBefore = mWethHost.balanceOf(address(this));

        amount = amount - DEFAULT_INFLATION_INCREASE;
        if (underlying) mWethHost.redeemUnderlying(amount);
        else mWethHost.redeem(amount);

        uint256 balanceWethAfter = weth.balanceOf(address(this));
        uint256 supplyMTokenAfter = mWethHost.totalSupply();
        uint256 balanceMTokenAfter = mWethHost.balanceOf(address(this));

        // it should transfer underlying to redeemer
        assertEq(balanceWethBefore + amount, balanceWethAfter);

        // it should decrease totalSupply of mToken
        assertGt(supplyMTokenBefore, supplyMTokenAfter);
        assertEq(supplyMTokenBefore - amount, supplyMTokenAfter);

        // it should decrease redeemer balance of mToken
        assertGt(balanceMTokenBefore, balanceMTokenAfter);
        assertEq(balanceMTokenBefore - amount, balanceMTokenAfter);
    }

    modifier whenRedeemExternalIsCalled() {
        // @dev does nothing; just for readability
        _;
    }

    modifier givenDecodedAmountIsValid() {
        // @dev does nothing; just for readability
        _;
    }

    modifier whenWithdrawOnExtensionIsCalled() {
        // @dev does nothing; just for readability
        _;
    }

    modifier givenDecodedLiquidityIsValid() {
        // @dev does nothing; just for readability
        _;
    }

    function test_GivenDecodedLiquidityIs0() external whenWithdrawOnExtensionIsCalled {
        vm.expectRevert(ImErc20Host.mErc20Host_AmountNotValid.selector);
        mWethHost.withdrawOnExtension(0, 1);
    }

    function test_RevertWhen_LiquiditySealVerificationFails(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenWithdrawOnExtensionIsCalled
        givenDecodedLiquidityIsValid
    {
        verifierMock.setStatus(true); // set for failure

        vm.expectRevert();
        mWethHost.withdrawOnExtension(amount, 1);
    }

    function test_WhenLiquiditySealVerificationWasOk(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenWithdrawOnExtensionIsCalled
        givenDecodedLiquidityIsValid
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
    {
        _borrowPrerequisites(address(mWethHost), amount);

        amount = amount - DEFAULT_INFLATION_INCREASE;

        uint256 balanceWethBefore = weth.balanceOf(address(this));
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        mWethHost.updateAllowedChain(1, true);
        mWethHost.withdrawOnExtension(amount, 1);

        uint256 balanceWethAfter = weth.balanceOf(address(this));
        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));

        // it should increse balanceOf account
        assertEq(balanceOfAfter + amount, balanceOfBefore, "B");

        // it should decrease total supply by amount
        assertGt(totalSupplyBefore, totalSupplyAfter, "C");
        assertEq(totalSupplyBefore - amount, totalSupplyAfter, "D");

        // it should transfer
        assertEq(balanceWethBefore, balanceWethAfter, "F");
    }
}
