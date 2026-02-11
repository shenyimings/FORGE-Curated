// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.17;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {
    CollateralDebtData,
    CollateralCalcTask,
    ICreditManagerV3,
    ICreditManagerV3Events,
    ManageDebtAction
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPriceFeedStore, PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {
    ICreditFacadeV3,
    ICreditFacadeV3Multicall,
    MultiCall
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {MultiCallBuilder} from "@gearbox-protocol/core-v3/contracts/test/lib/MultiCallBuilder.sol";
import {PERCENTAGE_FACTOR} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";

// TESTS
import "@gearbox-protocol/core-v3/contracts/test/lib/constants.sol";
import {IntegrationTestHelper} from "@gearbox-protocol/core-v3/contracts/test/helpers/IntegrationTestHelper.sol";

// EXCEPTIONS
import "@gearbox-protocol/core-v3/contracts/interfaces/IExceptions.sol";

// MOCKS
import {AdapterMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/core/AdapterMock.sol";
import {PriceFeedMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/oracles/PriceFeedMock.sol";

import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IContractsRegister} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IContractsRegister.sol";

import {TreasuryLiquidator} from "../emergency/TreasuryLiquidator.sol";

contract ERC4626Mock is ERC4626 {
    constructor(address asset, string memory name, string memory symbol) ERC4626(IERC20(asset)) ERC20(name, symbol) {}
}

contract TreasuryLiquidatorIntegrationTest is IntegrationTestHelper {
    TreasuryLiquidator treasuryLiquidator;
    address treasury;
    address liquidator;
    address marketConfigurator;
    ERC4626Mock wrappedUnderlying;

    // Events from TreasuryLiquidator
    event PartiallyLiquidateFromTreasury(
        address indexed creditFacade, address indexed creditAccount, address indexed liquidator
    );
    event SetLiquidatorStatus(address indexed liquidator, bool status);
    event SetMinExchangeRate(address indexed assetIn, address indexed assetOut, uint256 rate);

    function _setupTreasuryLiquidator() internal {
        treasury = makeAddr("TREASURY");
        liquidator = makeAddr("LIQUIDATOR");
        marketConfigurator = makeAddr("MARKET_CONFIGURATOR");

        // Deploy TreasuryLiquidator
        treasuryLiquidator = new TreasuryLiquidator(treasury, marketConfigurator);

        // Create wrapped underlying mock
        wrappedUnderlying = new ERC4626Mock(underlying, "Wrapped DAI", "wDAI");

        // Setup initial balances
        tokenTestSuite.mint(underlying, treasury, 1000000e18);

        // Deposit some underlying into wrapped version for treasury
        vm.startPrank(treasury);
        IERC20(underlying).approve(address(wrappedUnderlying), 500000e18);
        wrappedUnderlying.mint(500000e18, treasury);
        vm.stopPrank();
    }

    function _makeCreditAccount() internal returns (address) {
        uint256 debtAmount = DAI_ACCOUNT_AMOUNT;
        uint256 bufferedDebtAmount = 11 * debtAmount / 10;
        uint256 collateralAmount = priceOracle.convert(
            bufferedDebtAmount * PERCENTAGE_FACTOR / creditManager.liquidationThresholds(weth), underlying, weth
        );

        tokenTestSuite.mint(weth, USER, collateralAmount);
        tokenTestSuite.approve(weth, USER, address(creditManager));

        vm.prank(USER);
        return creditFacade.openCreditAccount(
            USER,
            MultiCallBuilder.build(
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.increaseDebt, (debtAmount))
                }),
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.withdrawCollateral, (underlying, debtAmount, USER))
                }),
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.addCollateral, (weth, collateralAmount))
                }),
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(
                        ICreditFacadeV3Multicall.updateQuota, (weth, int96(uint96(bufferedDebtAmount)), 0)
                    )
                })
            ),
            0
        );
    }

    function _setupContractsRegister(bool isValidCM) internal {
        // Mock the market configurator to return valid contracts register
        vm.mockCall(
            marketConfigurator,
            abi.encodeWithSelector(IMarketConfigurator.contractsRegister.selector),
            abi.encode(address(cr))
        );

        // Mock contracts register to validate credit manager
        vm.mockCall(
            address(cr),
            abi.encodeWithSelector(IContractsRegister.isCreditManager.selector, address(creditManager)),
            abi.encode(isValidCM)
        );
    }

    function _purgeWeth(address creditAccount) internal {
        CollateralDebtData memory cdd =
            creditManager.calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_COLLATERAL);

        uint256 debtEquivalent = priceOracle.convertFromUSD(cdd.totalDebtUSD, weth) * PERCENTAGE_FACTOR
            / creditManager.liquidationThresholds(weth);
        uint256 tokenBalance = tokenTestSuite.balanceOf(weth, creditAccount);

        vm.prank(creditAccount);
        IERC20(weth).transfer(address(1), tokenBalance - (debtEquivalent * 9999 / PERCENTAGE_FACTOR));
    }

    /// @dev I:[TL-1]: Constructor sets correct values
    function test_I_TL_01_constructor_sets_correct_values() public creditTest {
        _setupTreasuryLiquidator();
        assertEq(treasuryLiquidator.treasury(), treasury, "Treasury address mismatch");
        assertEq(treasuryLiquidator.marketConfigurator(), marketConfigurator, "Market configurator mismatch");
        assertEq(treasuryLiquidator.contractType(), "TREASURY_LIQUIDATOR", "Contract type mismatch");
        assertEq(treasuryLiquidator.version(), 3_10, "Version mismatch");
    }

    /// @dev I:[TL-2]: Constructor reverts on zero addresses
    function test_I_TL_02_constructor_reverts_on_zero_addresses() public {
        vm.expectRevert(ZeroAddressException.selector);
        new TreasuryLiquidator(address(0), makeAddr("MARKET_CONFIGURATOR"));

        vm.expectRevert(ZeroAddressException.selector);
        new TreasuryLiquidator(makeAddr("TREASURY"), address(0));
    }

    /// @dev I:[TL-3]: setLiquidatorStatus works correctly for treasury
    function test_I_TL_03_setLiquidatorStatus_works_correctly_for_treasury() public creditTest {
        _setupTreasuryLiquidator();
        assertFalse(treasuryLiquidator.isLiquidator(liquidator), "Liquidator should not be approved initially");

        vm.expectEmit(true, false, false, true);
        emit SetLiquidatorStatus(liquidator, true);

        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        assertTrue(treasuryLiquidator.isLiquidator(liquidator), "Liquidator should be approved");

        // Test revoking status
        vm.expectEmit(true, false, false, true);
        emit SetLiquidatorStatus(liquidator, false);

        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, false);

        assertFalse(treasuryLiquidator.isLiquidator(liquidator), "Liquidator should be revoked");
    }

    /// @dev I:[TL-4]: setLiquidatorStatus reverts for non-treasury
    function test_I_TL_04_setLiquidatorStatus_reverts_for_non_treasury() public creditTest {
        _setupTreasuryLiquidator();
        vm.expectRevert(TreasuryLiquidator.CallerNotTreasuryException.selector);
        vm.prank(USER);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);
    }

    /// @dev I:[TL-5]: setLiquidatorStatus reverts on zero address
    function test_I_TL_05_setLiquidatorStatus_reverts_on_zero_address() public creditTest {
        _setupTreasuryLiquidator();
        vm.expectRevert(ZeroAddressException.selector);
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(address(0), true);
    }

    /// @dev I:[TL-6]: setLiquidatorStatus does nothing if status unchanged
    function test_I_TL_06_setLiquidatorStatus_does_nothing_if_status_unchanged() public creditTest {
        _setupTreasuryLiquidator();
        // Set liquidator status to true
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        // Try to set the same status again - should not emit event
        vm.recordLogs();
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        // Check no events were emitted
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted for unchanged status");
    }

    /// @dev I:[TL-7]: setMinExchangeRate works correctly for treasury
    function test_I_TL_07_setMinExchangeRate_works_correctly_for_treasury() public creditTest {
        _setupTreasuryLiquidator();
        uint256 rate = 10050; // 1.005 in PERCENTAGE_FACTOR format

        assertEq(treasuryLiquidator.minExchangeRates(underlying, weth), 0, "Rate should be 0 initially");

        vm.expectEmit(true, true, false, true);
        emit SetMinExchangeRate(underlying, weth, rate);

        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, rate);

        assertEq(treasuryLiquidator.minExchangeRates(underlying, weth), rate, "Rate should be set correctly");
    }

    /// @dev I:[TL-8]: setMinExchangeRate reverts for non-treasury
    function test_I_TL_08_setMinExchangeRate_reverts_for_non_treasury() public creditTest {
        _setupTreasuryLiquidator();
        vm.expectRevert(TreasuryLiquidator.CallerNotTreasuryException.selector);
        vm.prank(USER);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, 10050);
    }

    /// @dev I:[TL-9]: setMinExchangeRate reverts on zero addresses
    function test_I_TL_09_setMinExchangeRate_reverts_on_zero_addresses() public creditTest {
        _setupTreasuryLiquidator();
        vm.expectRevert(ZeroAddressException.selector);
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(address(0), weth, 10050);

        vm.expectRevert(ZeroAddressException.selector);
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, address(0), 10050);
    }

    /// @dev I:[TL-10]: setMinExchangeRate does nothing if rate unchanged
    function test_I_TL_10_setMinExchangeRate_does_nothing_if_rate_unchanged() public creditTest {
        _setupTreasuryLiquidator();
        uint256 rate = 10050;

        // Set rate initially
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, rate);

        // Try to set the same rate again - should not emit event
        vm.recordLogs();
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, rate);

        // Check no events were emitted
        assertEq(vm.getRecordedLogs().length, 0, "No events should be emitted for unchanged rate");
    }

    /// @dev I:[TL-11]: partiallyLiquidateFromTreasury reverts for non-liquidator
    function test_I_TL_11_partiallyLiquidateFromTreasury_reverts_for_non_liquidator() public creditTest {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _setupContractsRegister(true);

        vm.expectRevert(TreasuryLiquidator.CallerNotApprovedLiquidatorException.selector);
        vm.prank(USER);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, 1000e18, new PriceUpdate[](0), address(0)
        );
    }

    /// @dev I:[TL-12]: partiallyLiquidateFromTreasury reverts for invalid credit suite
    function test_I_TL_12_partiallyLiquidateFromTreasury_reverts_for_invalid_credit_suite() public creditTest {
        _setupTreasuryLiquidator();
        _setupContractsRegister(false);
        address creditAccount = _makeCreditAccount();

        // Setup liquidator
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        // Don't setup valid credit suite - should revert
        vm.expectRevert(TreasuryLiquidator.InvalidCreditSuiteException.selector);
        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, 1000e18, new PriceUpdate[](0), address(0)
        );
    }

    /// @dev I:[TL-13]: partiallyLiquidateFromTreasury reverts for unsupported token pair
    function test_I_TL_13_partiallyLiquidateFromTreasury_reverts_for_unsupported_token_pair() public creditTest {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _setupContractsRegister(true);

        // Setup liquidator
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        // Don't set exchange rate - should revert
        vm.expectRevert(TreasuryLiquidator.UnsupportedTokenPairException.selector);
        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, 1000e18, new PriceUpdate[](0), address(0)
        );
    }

    /// @dev I:[TL-14]: partiallyLiquidateFromTreasury reverts for insufficient treasury funds
    function test_I_TL_14_partiallyLiquidateFromTreasury_reverts_for_insufficient_treasury_funds() public creditTest {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _setupContractsRegister(true);

        // Setup liquidator and exchange rate
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, 10050);

        // Remove treasury funds
        vm.startPrank(treasury);
        IERC20(underlying).transfer(USER, IERC20(underlying).balanceOf(treasury));
        vm.stopPrank();

        vm.expectRevert(TreasuryLiquidator.InsufficientTreasuryFundsException.selector);
        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, 1000e18, new PriceUpdate[](0), address(0)
        );
    }

    /// @dev I:[TL-15]: partiallyLiquidateFromTreasury reverts for insufficient wrapped treasury funds
    function test_I_TL_15_partiallyLiquidateFromTreasury_reverts_for_insufficient_wrapped_treasury_funds()
        public
        creditTest
    {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _setupContractsRegister(true);

        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, 10050);

        vm.startPrank(treasury);
        wrappedUnderlying.redeem(wrappedUnderlying.balanceOf(treasury), treasury, treasury);
        vm.stopPrank();

        vm.expectRevert(TreasuryLiquidator.InsufficientTreasuryFundsException.selector);
        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, 1000e18, new PriceUpdate[](0), address(wrappedUnderlying)
        );
    }

    /// @dev I:[TL-16]: partiallyLiquidateFromTreasury works correctly with direct underlying
    function test_I_TL_16_partiallyLiquidateFromTreasury_works_correctly_with_direct_underlying() public creditTest {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _purgeWeth(creditAccount);
        _setupContractsRegister(true);

        vm.roll(block.number + 1);

        // Setup liquidator and exchange rate
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        uint256 rate = 9;
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, rate);

        uint256 repaidAmount = 1000e18;
        uint256 treasuryBalanceBefore = IERC20(underlying).balanceOf(treasury);
        uint256 treasuryWethBalanceBefore = IERC20(weth).balanceOf(treasury);

        // Approve treasury to spend from treasury (for transferFrom)
        vm.prank(treasury);
        IERC20(underlying).approve(address(treasuryLiquidator), repaidAmount);

        vm.expectEmit(true, true, true, false);
        emit PartiallyLiquidateFromTreasury(address(creditFacade), creditAccount, liquidator);

        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, repaidAmount, new PriceUpdate[](0), address(0)
        );

        assertEq(
            IERC20(underlying).balanceOf(treasury),
            treasuryBalanceBefore - repaidAmount,
            "Treasury underlying balance should decrease"
        );

        assertGt(
            IERC20(weth).balanceOf(treasury),
            treasuryWethBalanceBefore + 9e17,
            "Treasury should receive at least 9e17 weth"
        );
    }

    /// @dev I:[TL-17]: partiallyLiquidateFromTreasury works correctly with wrapped underlying
    function test_I_TL_17_partiallyLiquidateFromTreasury_works_correctly_with_wrapped_underlying() public creditTest {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _purgeWeth(creditAccount);
        _setupContractsRegister(true);

        vm.roll(block.number + 1);

        // Setup liquidator and exchange rate
        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        uint256 rate = 9;
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, rate);

        uint256 repaidAmount = 1000e18;
        uint256 treasuryWrappedBalanceBefore = wrappedUnderlying.maxWithdraw(treasury);
        uint256 treasuryWethBalanceBefore = IERC20(weth).balanceOf(treasury);

        vm.prank(treasury);
        IERC20(wrappedUnderlying).approve(address(treasuryLiquidator), treasuryWrappedBalanceBefore);

        vm.expectEmit(true, true, true, false);
        emit PartiallyLiquidateFromTreasury(address(creditFacade), creditAccount, liquidator);

        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, repaidAmount, new PriceUpdate[](0), address(wrappedUnderlying)
        );
        
        assertEq(
            wrappedUnderlying.maxWithdraw(treasury),
            treasuryWrappedBalanceBefore - repaidAmount,
            "Treasury wrapped balance is incorrect"
        );

        assertGt(
            IERC20(weth).balanceOf(treasury),
            treasuryWethBalanceBefore + 9e17,
            "Treasury should receive at least 9e17 weth"
        );
    }

    /// @dev I:[TL-18]: partiallyLiquidateFromTreasury calculates minimum seized amount correctly
    function test_I_TL_18_partiallyLiquidateFromTreasury_calculates_minimum_seized_amount_correctly()
        public
        creditTest
    {
        _setupTreasuryLiquidator();
        address creditAccount = _makeCreditAccount();
        _purgeWeth(creditAccount);
        _setupContractsRegister(true);

        vm.roll(block.number + 1);

        vm.prank(treasury);
        treasuryLiquidator.setLiquidatorStatus(liquidator, true);

        uint256 rate = 9;
        vm.prank(treasury);
        treasuryLiquidator.setMinExchangeRate(underlying, weth, rate);

        uint256 repaidAmount = 1000e18;

        uint256 scaleUnderlying = 10 ** IERC20Metadata(underlying).decimals(); // 18
        uint256 scaleWeth = 10 ** IERC20Metadata(weth).decimals(); // 18
        uint256 expectedMinSeized = repaidAmount * rate * scaleWeth / (PERCENTAGE_FACTOR * scaleUnderlying);

        assertEq(expectedMinSeized, 9e17, "Expected minimum seized amount calculation");
        vm.prank(treasury);
        IERC20(underlying).approve(address(treasuryLiquidator), repaidAmount);

        vm.expectCall(
            address(creditFacade),
            abi.encodeWithSelector(
                ICreditFacadeV3.partiallyLiquidateCreditAccount.selector,
                creditAccount,
                weth,
                repaidAmount,
                expectedMinSeized,
                treasury,
                new PriceUpdate[](0)
            )
        );

        vm.prank(liquidator);
        treasuryLiquidator.partiallyLiquidateFromTreasury(
            address(creditFacade), creditAccount, weth, repaidAmount, new PriceUpdate[](0), address(0)
        );
    }
}
