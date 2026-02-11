// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// interfaces
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

// contracts
import {Operator} from "src/Operator/Operator.sol";
import {OperatorStorage} from "src/Operator/OperatorStorage.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mErc20Host_mint is mToken_Unit_Shared {
    function setUp() public virtual override {
        super.setUp();

        mWethHost.updateAllowedChain(uint32(block.chainid), true);
    }

    function test_RevertGiven_MarketIsPausedForMinting(uint256 amount)
        external
        whenPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_Paused.selector);
        mWethHost.mint(amount, address(this), amount);
    }

    function test_RevertGiven_MarketIsNotListed(uint256 amount)
        external
        whenNotPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint)
        inRange(amount, SMALL, LARGE)
    {
        vm.expectRevert(OperatorStorage.Operator_MarketNotListed.selector);
        mWethHost.mint(amount, address(this), amount);
    }

    function test_RevertGiven_WhenSupplyCapIsReached(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenSupplyCapReached(address(mWethHost), amount)
        whenMarketIsListed(address(mWethHost))
    {
        _getTokens(weth, address(this), amount);
        weth.approve(address(mWethHost), amount);

        vm.expectRevert(OperatorStorage.Operator_MarketSupplyReached.selector);
        mWethHost.mint(amount, address(this), amount);
        // it should revert with Operator_MarketSupplyReached
    }

    function test_WhenSupplyCapIsGreater(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMarketIsListed(address(mWethHost))
    {
        _getTokens(weth, address(this), amount);
        weth.approve(address(mWethHost), amount);

        uint256 balanceWethBefore = weth.balanceOf(address(this));
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));
        mWethHost.mint(amount, address(this), amount);

        uint256 balanceWethAfter = weth.balanceOf(address(this));
        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));

        // it should increse balanceOf account
        assertGt(balanceOfAfter, balanceOfBefore);

        // it should increase total supply by amount
        assertGt(totalSupplyAfter, totalSupplyBefore);

        // it should transfer underlying from user
        assertGt(balanceWethBefore, balanceWethAfter);

        assertEq(totalSupplyAfter - amount, totalSupplyBefore);
    }

    function test_GivenAmountIs0() external whenMarketIsListed(address(mWethHost)) {
        uint256 amount = 0;
        vm.expectRevert(); //arithmetic underflow or overflow
        mWethHost.mint(amount, address(this), amount);
    }

    modifier whenMintExternalIsCalled() {
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
        whenMintExternalIsCalled
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectRevert(ImErc20Host.mErc20Host_JournalNotValid.selector);
        mWethHost.mintExternal("", "0x123", amounts, amounts, address(this));
    }

    function test_RevertGiven_JournalIsNonEmptyButLengthIsNotValid(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectRevert(ImErc20Host.mErc20Host_JournalNotValid.selector);
        mWethHost.mintExternal("", "0x123", amounts, amounts, address(this));
    }

    function test_GivenDecodedAmountIs0() external whenMintExternalIsCalled whenMarketIsListed(address(mWethHost)) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), 0);

        vm.expectRevert(ImErc20Host.mErc20Host_AmountNotValid.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));
    }

    function test_RevertWhen_SealVerificationFails(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes[] memory journals = new bytes[](1);
        journals[0] = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);
        bytes memory journalData = abi.encode(journals);

        verifierMock.setStatus(true); // set for failure

        vm.expectRevert();
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));
    }

    function test_WhenSealVerificationWasOk(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
    {
        uint256 balanceWethBefore = weth.balanceOf(address(this));
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        uint256 balanceWethAfter = weth.balanceOf(address(this));
        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));

        // it should increse balanceOf account
        assertGt(balanceOfAfter, balanceOfBefore);

        // it should increase total supply by amount
        assertGt(totalSupplyAfter, totalSupplyBefore);

        // it should transfer underlying from user
        assertEq(balanceWethBefore, balanceWethAfter);

        assertEq(totalSupplyAfter - amount, totalSupplyBefore);
    }

    function test_SetReserveFactor(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
    {
        mWethHost.setReserveFactor(1e17);
    }

    function test_WhenSealVerificationWasOk_And_OverflowLimitIsInPlace(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE36)
    {
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount * 20);

        Operator(operator).setOutflowTimeLimitInUSD(amount * 1e8 + 1);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        vm.expectRevert(OperatorStorage.Operator_OutflowVolumeReached.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        vm.warp(block.timestamp + 2 hours);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        vm.expectRevert(OperatorStorage.Operator_OutflowVolumeReached.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));
        vm.warp(block.timestamp + 1);
        vm.expectRevert(OperatorStorage.Operator_OutflowVolumeReached.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        vm.warp(block.timestamp + 2 hours);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));

        // it should increse balanceOf account
        assertGt(balanceOfAfter, balanceOfBefore);

        // it should increase total supply by amount
        assertGt(totalSupplyAfter, totalSupplyBefore);
    }

    function test_WhenSealVerificationWasOk_And_OverflowLimitNotExceeded(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
    {
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount * 10);

        Operator(operator).setOutflowTimeLimitInUSD(amount * 50);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));
        assertGt(balanceOfAfter, balanceOfBefore);
        assertEq(totalSupplyAfter, totalSupplyBefore + 2 * amount);
    }

    function test_WhenSealVerificationWasOk_And_OverflowLimitNotExceeded_ButUserIsBlacklisted(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
    {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount * 10);

        Operator(operator).setOutflowTimeLimitInUSD(amount * 50);
        blacklister.blacklist(address(this));
        vm.expectRevert(OperatorStorage.Operator_UserBlacklisted.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));
    }

    function test_WhenSealVerificationWasOk_And_AmountIsZero()
        external
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE)
    {
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), 0);

        Operator(operator).setOutflowTimeLimitInUSD(100);

        vm.expectRevert(ImErc20Host.mErc20Host_AmountNotValid.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));

        assertEq(balanceOfAfter, balanceOfBefore);
        assertEq(totalSupplyAfter, totalSupplyBefore);
    }

    function test_WhenSealVerificationWasOk_And_OutflowLimitIsAdjusted(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
        whenUnderlyingPriceIs(DEFAULT_ORACLE_PRICE36)
    {
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount * 20);

        Operator(operator).setOutflowTimeLimitInUSD(amount * 1e8 * 2 - 1);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        vm.expectRevert(OperatorStorage.Operator_OutflowVolumeReached.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        Operator(operator).setOutflowTimeLimitInUSD(amount * 1e8 * 50);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));
        assertGt(balanceOfAfter, balanceOfBefore);
        assertGt(totalSupplyAfter, totalSupplyBefore);
    }

    function test_WhenSealVerificationWasOk_ButWhitelistEnabled(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenMintExternalIsCalled
        givenDecodedAmountIsValid
        whenMarketIsListed(address(mWethHost))
    {
        uint256 balanceWethBefore = weth.balanceOf(address(this));
        uint256 totalSupplyBefore = mWethHost.totalSupply();
        uint256 balanceOfBefore = mWethHost.balanceOf(address(this));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory journalData = _createAccumulatedAmountJournal(address(this), address(mWethHost), amount);

        operator.enableWhitelist();

        vm.expectRevert(OperatorStorage.Operator_UserNotWhitelisted.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        operator.setWhitelistedUser(address(this), false);
        vm.expectRevert(OperatorStorage.Operator_UserNotWhitelisted.selector);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        operator.setWhitelistedUser(address(this), true);
        mWethHost.mintExternal(journalData, "0x123", amounts, amounts, address(this));

        uint256 balanceWethAfter = weth.balanceOf(address(this));
        uint256 totalSupplyAfter = mWethHost.totalSupply();
        uint256 balanceOfAfter = mWethHost.balanceOf(address(this));

        // it should increse balanceOf account
        assertGt(balanceOfAfter, balanceOfBefore);

        // it should increase total supply by amount
        assertGt(totalSupplyAfter, totalSupplyBefore);

        // it should transfer underlying from user
        assertEq(balanceWethBefore, balanceWethAfter);

        assertEq(totalSupplyAfter - amount, totalSupplyBefore);
    }
}
