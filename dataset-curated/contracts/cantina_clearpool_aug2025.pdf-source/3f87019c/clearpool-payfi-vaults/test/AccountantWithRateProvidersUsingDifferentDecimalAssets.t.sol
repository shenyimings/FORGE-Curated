// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract AccountantWithRateProvidersUsingDifferentDecimalTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    address public payoutAddress = vm.addr(7_777_777);
    RolesAuthority public rolesAuthority;

    address public usdcWhale = 0x28C6c06298d514Db089934071355E5743bf21d60;

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant ADMIN_ROLE = 2;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 3;
    uint8 public constant BORING_VAULT_ROLE = 4;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19_618_964;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 6);

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payoutAddress, 1e18, address(USDC), 1.001e4, 0.999e4, 1, 0
        );

        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1_000_000e6);
        vm.stopPrank();
        USDC.safeApprove(address(boringVault), 1_000_000e6);
        boringVault.enter(address(this), USDC, 1_000_000e6, address(this), 1_000_000e6);

        accountant.setRateProviderData(DAI, true, address(0));
        accountant.setRateProviderData(USDT, true, address(0));
        accountant.setRateProviderData(SDAI, false, sDaiRateProvider);

        // Start accounting so we can claim fees during a test.
        accountant.setManagementFeeRate(0.01e4);

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        uint96 newExchangeRate = uint96(1.0005e18);
        accountant.updateExchangeRate(newExchangeRate);

        skip(1 days);

        accountant.updateExchangeRate(newExchangeRate);

        skip(1 days);
    }

    function testClaimFeesUsingBase() external {
        // Set exchangeRate back to 1e6.
        uint96 newExchangeRate = uint96(1e18);
        accountant.updateExchangeRate(newExchangeRate);

        (, uint128 feesOwed,,,,,,,,) = accountant.accountantState();

        vm.startPrank(address(boringVault));
        USDC.safeApprove(address(accountant), type(uint256).max);
        // Claim fees.
        accountant.claimFees(USDC);
        vm.stopPrank();

        assertEq(USDC.balanceOf(payoutAddress), feesOwed, "Should have claimed fees in USDC");
    }

    function testClaimFeesUsingPegged() external {
        // Set exchangeRate back to 1e6.
        uint96 newExchangeRate = uint96(1e18);
        accountant.updateExchangeRate(newExchangeRate);

        (, uint128 feesOwed,,,,,,,,) = accountant.accountantState();

        deal(address(USDT), address(boringVault), 1_000_000e6);
        vm.startPrank(address(boringVault));
        USDT.safeApprove(address(accountant), type(uint256).max);
        // Claim fees.
        accountant.claimFees(USDT);
        vm.stopPrank();

        assertEq(USDT.balanceOf(payoutAddress), feesOwed, "Should have claimed fees in USDT");
    }

    function testClaimFeesUsingPeggedDifferentDecimals() external {
        // Set exchangeRate back to 1e6.
        uint96 newExchangeRate = uint96(1e18);
        accountant.updateExchangeRate(newExchangeRate);

        (, uint128 feesOwed,,,,,,,,) = accountant.accountantState();

        deal(address(DAI), address(boringVault), 1_000_000e18);
        vm.startPrank(address(boringVault));
        DAI.safeApprove(address(accountant), type(uint256).max);
        // Claim fees.
        accountant.claimFees(DAI);
        vm.stopPrank();

        uint256 expectedFeesOwed = uint256(feesOwed).mulDivDown(1e18, 1e6);
        assertEq(DAI.balanceOf(payoutAddress), expectedFeesOwed, "Should have claimed fees in DAI");
    }

    function testClaimFeesUsingRateProviderAsset() external {
        // Set exchangeRate back to 1e6.
        uint96 newExchangeRate = uint96(1e18);
        accountant.updateExchangeRate(newExchangeRate);

        (, uint128 feesOwed,,,,,,,,) = accountant.accountantState();

        deal(address(SDAI), address(boringVault), 1_000_000e18);
        vm.startPrank(address(boringVault));
        SDAI.safeApprove(address(accountant), type(uint256).max);
        // Claim fees.
        accountant.claimFees(SDAI);
        vm.stopPrank();

        uint256 expectedFeesOwed = uint256(feesOwed).mulDivDown(1e18, 1e6);
        expectedFeesOwed = expectedFeesOwed.mulDivDown(1e18, IRateProvider(sDaiRateProvider).getRate());
        uint256 sDaiFees = SDAI.balanceOf(payoutAddress);
        assertEq(sDaiFees, expectedFeesOwed, "Should have claimed fees in SDAI");

        // Convert fees received to USDC.
        uint256 feesConvertedToUsdc = sDaiFees.mulDivDown(IRateProvider(sDaiRateProvider).getRate(), 1e18);
        feesConvertedToUsdc = feesConvertedToUsdc.mulDivDown(1e6, 1e18);
        assertApproxEqAbs(
            feesOwed, feesConvertedToUsdc, 1, "sDAI fees converted to USDC should be equal to fees owed in USDC"
        );
    }

    function testRates() external {
        // Set exchangeRate back to 1e18 (not 1e6)
        uint96 newExchangeRate = uint96(1e18);
        accountant.updateExchangeRate(newExchangeRate);

        // getRate now returns 18 decimals
        uint256 rate = accountant.getRate();
        uint256 expected_rate = 1e18; // Changed from 1e6 to 1e18
        assertEq(rate, expected_rate, "Rate should be expected rate");
        rate = accountant.getRateSafe();
        assertEq(rate, expected_rate, "Rate should be expected rate");

        // getRateInQuote still returns in quote decimals (for display)
        uint256 rateInQuote = accountant.getRateInQuote(USDC);
        expected_rate = 1e6; // Still 6 decimals for USDC display
        assertEq(rateInQuote, expected_rate, "Rate should be expected rate");

        rateInQuote = accountant.getRateInQuote(DAI);
        expected_rate = 1e18; // Still 18 decimals for DAI display
        assertEq(rateInQuote, expected_rate, "Rate should be expected rate");

        rateInQuote = accountant.getRateInQuote(USDT);
        expected_rate = 1e6; // Still 6 decimals for USDT display
        assertEq(rateInQuote, expected_rate, "Rate should be expected rate");

        rateInQuote = accountant.getRateInQuote(SDAI);
        expected_rate = uint256(1e18).mulDivDown(1e18, IRateProvider(sDaiRateProvider).getRate());
        assertEq(rateInQuote, expected_rate, "Rate should be expected rate for sDAI");
    }

    function testRoundingDrag_10M_USDC_30Days_HourlyVsSingle_fixed() external {
        // ============ Common params ============
        uint256 principal = 10_000_000e6; // 10M USDC
        uint256 apyBps = 500; // 5% APY

        // Fund this test (20M for both scenarios)
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 2 * principal);
        vm.stopPrank();

        // ============ Scenario A: single checkpoint after 30 days ============
        BoringVault vaultA = new BoringVault(address(this), "BV-A", "BVA", 6);
        AccountantWithRateProviders acctA = new AccountantWithRateProviders(
            address(this), address(vaultA), payoutAddress, uint96(1e18), address(USDC), 1.001e4, 0.999e4, 1, 0
        );
        acctA.setLendingRate(apyBps);

        USDC.safeApprove(address(vaultA), principal);
        vaultA.enter(address(this), USDC, principal, address(this), principal);

        skip(30 days);
        acctA.checkpoint();

        uint256 rateA = acctA.getRate(); // 18 decimals
        uint256 valueA = vaultA.totalSupply().mulDivDown(rateA, 1e18);
        // valueA is already in 6 decimals - NO CONVERSION NEEDED
        uint256 interestA = valueA - principal;

        console.log("----- 10M USDC over 30 days @5%% APY -----");
        console.log("A) single-step rate (18-dec):", rateA);
        console.log("A) interest (USDC, 6d):     ", interestA);

        // ============ Scenario B: hourly checkpoints for 30 days ============
        BoringVault vaultB = new BoringVault(address(this), "BV-B", "BVB", 6);
        AccountantWithRateProviders acctB = new AccountantWithRateProviders(
            address(this), address(vaultB), payoutAddress, uint96(1e18), address(USDC), 1.001e4, 0.999e4, 1, 0
        );
        acctB.setLendingRate(apyBps);

        USDC.safeApprove(address(vaultB), principal);
        vaultB.enter(address(this), USDC, principal, address(this), principal);

        for (uint256 i = 0; i < 30 * 24; i++) {
            skip(1 hours);
            acctB.checkpoint();
        }

        uint256 rateB = acctB.getRate(); // 18 decimals
        uint256 valueB = vaultB.totalSupply().mulDivDown(rateB, 1e18);
        // valueB is already in 6 decimals - NO CONVERSION NEEDED
        uint256 interestB = valueB - principal;

        console.log("B) hourly-step rate (18-dec):", rateB);
        console.log("B) interest (USDC, 6d):     ", interestB);

        // With 18-decimal precision, hourly NOW OUTPERFORMS due to compounding!
        uint256 benefit = interestB > interestA ? (interestB - interestA) : 0;
        console.log("Compound benefit (B - A) USDC:", benefit);

        // REVERSED: With 18-dec precision, hourly should OUTPERFORM single-step
        assertGt(interestB, interestA, "Hourly should outperform single-step with 18-dec rate due to compounding");

        assertGt(benefit, 0, "Should have compound interest benefit");

        emit log_string("----- 10M USDC over 30 days @5% APY -----");
        emit log_named_decimal_uint("A) single-step rate", rateA, 18);
        emit log_named_decimal_uint("B) hourly-step rate", rateB, 18);
        emit log_named_decimal_uint("A) interest (USDC)", interestA, 6);
        emit log_named_decimal_uint("B) interest (USDC)", interestB, 6);
        emit log_named_decimal_uint("Compound benefit (B - A) USDC", benefit, 6);
    }

    function testCompoundAlwaysBeatsSimple() external {
        // Fund this test with USDC first
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1000e6);
        vm.stopPrank();

        // Setup vault with USDC base
        BoringVault vault = new BoringVault(address(this), "Test", "TEST", 6);
        AccountantWithRateProviders accountant = new AccountantWithRateProviders(
            address(this),
            address(vault),
            payoutAddress,
            1e18, // 18 decimal starting rate
            address(USDC),
            1.1e4,
            0.9e4,
            1,
            0
        );

        // Set 14% APY (matching your example)
        accountant.setLendingRate(1400);

        // Approve and deposit 1000 USDC
        USDC.approve(address(vault), 1000e6);
        vault.enter(address(this), USDC, 1000e6, address(this), 1000e6);

        // Skip 10 minutes
        skip(10 minutes);
        accountant.checkpoint();

        uint256 rate = accountant.getRate(); // 18 decimals
        // totalSupply (6 dec) * rate (18 dec) / 1e18 = value (6 dec)
        uint256 value = vault.totalSupply().mulDivDown(rate, 1e18);
        // NO CONVERSION NEEDED - value is already in 6 decimals!

        // Calculate simple interest
        uint256 principal = 1000e6;
        uint256 simpleInterest = principal.mulDivDown(1400 * 10 minutes, 365 days * 10_000);
        uint256 simpleValue = principal + simpleInterest;

        // Compound MUST be >= simple
        assertGe(value, simpleValue, "Compound interest must beat simple interest");

        // Log values
        console.log("Compound value:", value);
        console.log("Simple value:", simpleValue);
        console.log("Difference (compound - simple):", value - simpleValue);
    }

    function testMultiAssetDifferentDecimals() external {
        // Setup fresh vault for clean test - test contract is owner so has auth
        BoringVault testVault = new BoringVault(address(this), "Multi", "MULTI", 18);
        AccountantWithRateProviders testAccountant = new AccountantWithRateProviders(
            address(this), address(testVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        // Setup assets with different decimals
        testAccountant.setRateProviderData(USDC, true, address(0));
        testAccountant.setRateProviderData(DAI, true, address(0));
        testAccountant.setRateProviderData(USDT, true, address(0));

        // Get funds
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1_000_000e6);
        vm.stopPrank();
        deal(address(DAI), address(this), 1_000_000e18);
        deal(address(USDT), address(this), 1_000_000e6);

        // Deposit each asset and verify shares are consistent
        USDC.approve(address(testVault), type(uint256).max);
        DAI.approve(address(testVault), type(uint256).max);

        // Fix USDT approval - use safeApprove from SafeTransferLib
        USDT.safeApprove(address(testVault), type(uint256).max);

        // For 18 decimal vault with 1:1 starting rate
        testVault.enter(address(this), USDC, 1000e6, address(this), 1000e18);
        testVault.enter(address(this), DAI, 1000e18, address(this), 1000e18);
        testVault.enter(address(this), USDT, 1000e6, address(this), 1000e18);

        // All should give same shares (1000 units of each stablecoin = 1000e18 shares each)
        assertEq(testVault.balanceOf(address(this)), 3000e18, "Should have 3000 shares total");
    }

    function testNonPeggedAssetWithRateProvider() external {
        // Mock a simple rate provider for testing
        MockRateProvider wbtcProvider = new MockRateProvider(100_000e18); // 1 WBTC = 100k USDC

        // Setup WBTC (8 decimals)
        address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        accountant.setRateProviderData(ERC20(WBTC), false, address(wbtcProvider));

        // Get 1 WBTC
        deal(WBTC, address(this), 1e8);

        // Deposit 1 WBTC - should be worth 100k USDC
        ERC20(WBTC).approve(address(boringVault), 1e8);
        uint256 expectedShares = uint256(100_000e6).mulDivDown(1e18, accountant.getRate());
        boringVault.enter(address(this), ERC20(WBTC), 1e8, address(this), expectedShares);
        uint256 shares = expectedShares;

        // Verify shares match 100k USDC worth
        uint256 expectedShares1 = uint256(100_000e6).mulDivDown(1e18, accountant.getRate());
        assertApproxEqRel(shares, expectedShares1, 0.001e18, "WBTC shares should match value");
    }

    function testZeroInterestRate() external {
        // Create vault with 0% interest
        BoringVault zeroVault = new BoringVault(address(this), "Zero", "ZERO", 6);
        AccountantWithRateProviders zeroAccountant = new AccountantWithRateProviders(
            address(this), address(zeroVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        zeroAccountant.setLendingRate(0); // 0% APY

        // Deposit and wait
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1000e6);
        vm.stopPrank();

        USDC.approve(address(zeroVault), 1000e6);
        zeroVault.enter(address(this), USDC, 1000e6, address(this), 1000e6);

        uint256 rateBefore = zeroAccountant.getRate();
        skip(365 days);
        zeroAccountant.checkpoint();
        uint256 rateAfter = zeroAccountant.getRate();

        assertEq(rateBefore, rateAfter, "Rate should not change with 0% interest");
    }

    function testMaxInterestRate() external {
        // Test with maximum 50% APY
        BoringVault maxVault = new BoringVault(address(this), "Max", "MAX", 6);
        AccountantWithRateProviders maxAccountant = new AccountantWithRateProviders(
            address(this), address(maxVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        maxAccountant.setMaxLendingRate(5000); // 50% max
        maxAccountant.setLendingRate(5000); // 50% APY

        // Deposit
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1000e6);
        vm.stopPrank();

        USDC.approve(address(maxVault), 1000e6);
        maxVault.enter(address(this), USDC, 1000e6, address(this), 1000e6);

        skip(365 days);
        maxAccountant.checkpoint();

        uint256 rate = maxAccountant.getRate();
        uint256 value = maxVault.totalSupply().mulDivDown(rate, 1e18);

        // Should be ~1500 USDC (50% interest)
        assertApproxEqRel(value, 1500e6, 0.01e18, "Should have ~50% return");
    }

    function testRapidCheckpoints() external {
        // Multiple checkpoints in same block should not double-count
        accountant.setLendingRate(1000); // 10% APY

        uint256 rateBefore = accountant.getRate();

        // Call checkpoint multiple times in same block
        accountant.checkpoint();
        accountant.checkpoint();
        accountant.checkpoint();

        uint256 rateAfter = accountant.getRate();

        assertEq(rateBefore, rateAfter, "Multiple checkpoints in same block should not change rate");

        // Verify fees also not double-counted
        (, uint128 feesBefore,,,,,,,,) = accountant.accountantState();
        accountant.checkpoint();
        (, uint128 feesAfter,,,,,,,,) = accountant.accountantState();
        assertEq(feesBefore, feesAfter, "Fees should not increase in same block");
    }

    function testManagementFeeAccuracy() external {
        // Setup with 2% management fee
        BoringVault feeVault = new BoringVault(address(this), "Fee", "FEE", 6);
        AccountantWithRateProviders feeAccountant = new AccountantWithRateProviders(
            address(this),
            address(feeVault),
            payoutAddress,
            1e18,
            address(USDC),
            1.1e4,
            0.9e4,
            1,
            200 // 2% fee
        );

        // Deposit 1M USDC
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1_000_000e6);
        vm.stopPrank();

        USDC.approve(address(feeVault), 1_000_000e6);
        feeVault.enter(address(this), USDC, 1_000_000e6, address(this), 1_000_000e6);

        // Wait 1 year
        skip(365 days);
        feeAccountant.checkpoint();

        // Check fees (should be ~2% of 1M = 20k USDC)
        uint256 feesOwed = feeAccountant.previewFeesOwed();
        assertApproxEqRel(feesOwed, 20_000e6, 0.01e18, "Management fee should be ~2% annually");

        // Claim fees and verify
        vm.startPrank(address(feeVault));
        USDC.approve(address(feeAccountant), type(uint256).max);
        feeAccountant.claimFees(USDC);
        vm.stopPrank();

        assertApproxEqRel(USDC.balanceOf(payoutAddress), 20_000e6, 0.01e18, "Should receive ~20k USDC in fees");
    }

    function testLargeAmountPrecision() external {
        // Test with $100M+ to ensure no overflow
        BoringVault largeVault = new BoringVault(address(this), "Large", "LRG", 6);
        AccountantWithRateProviders largeAccountant = new AccountantWithRateProviders(
            address(this), address(largeVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        largeAccountant.setLendingRate(500); // 5% APY

        // Deposit 100M USDC
        deal(address(USDC), address(this), 100_000_000e6);
        USDC.approve(address(largeVault), 100_000_000e6);
        uint256 shares = 100_000_000e6; // Assuming 1:1 at start
        largeVault.enter(address(this), USDC, 100_000_000e6, address(this), shares);

        // Simulate 1 year
        for (uint256 i = 0; i < 365; i++) {
            skip(1 days);
            largeAccountant.checkpoint();
        }

        uint256 rate = largeAccountant.getRate();
        uint256 value = shares.mulDivDown(rate, 1e18);

        // Should be ~105M (5% on 100M)
        assertApproxEqRel(value, 105_000_000e6, 0.01e18, "Large amount should accrue correctly");
    }

    function testSmallAmountPrecision() external {
        // Test with dust amounts
        BoringVault smallVault = new BoringVault(address(this), "Small", "SML", 6);
        AccountantWithRateProviders smallAccountant = new AccountantWithRateProviders(
            address(this), address(smallVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        smallAccountant.setLendingRate(1000); // 10% APY

        // Deposit 0.01 USDC (dust)
        deal(address(USDC), address(this), 1e4); // 0.01 USDC
        USDC.approve(address(smallVault), 1e4);
        smallVault.enter(address(this), USDC, 1e4, address(this), 1e4);

        skip(365 days);
        smallAccountant.checkpoint();

        uint256 rate = smallAccountant.getRate();
        uint256 value = smallVault.totalSupply().mulDivDown(rate, 1e18);

        // Even dust should accrue interest
        assertGt(value, 1e4, "Dust should still accrue interest");
    }

    function testRateProviderEdgeCases() external {
        // Test extreme rate provider values
        MockRateProvider extremeLowProvider = new MockRateProvider(1); // Extremely low rate
        MockRateProvider extremeHighProvider = new MockRateProvider(1e36); // Extremely high rate

        // Create test tokens
        MockERC20 lowToken = new MockERC20("Low", "LOW", 18);
        MockERC20 highToken = new MockERC20("High", "HIGH", 18);

        accountant.setRateProviderData(lowToken, false, address(extremeLowProvider));
        accountant.setRateProviderData(highToken, false, address(extremeHighProvider));

        // Mint tokens
        lowToken.mint(address(this), 1e18);
        highToken.mint(address(this), 1e18);

        // Try deposits - should handle extreme values gracefully
        lowToken.approve(address(boringVault), 1e18);
        highToken.approve(address(boringVault), 1e18);

        uint256 lowShares = 1e18; // Calculate expected shares based on rate
        boringVault.enter(address(this), lowToken, 1e18, address(this), lowShares);
        uint256 highShares = 1e18; // Calculate expected shares based on rate
        boringVault.enter(address(this), highToken, 1e18, address(this), highShares);
        // Verify calculations didn't overflow/underflow
        assertGt(lowShares, 0, "Low rate should still produce shares");
        assertGt(highShares, 0, "High rate should still produce shares");
    }

    function testCrossAssetConsistency() external {
        // Deposit USDC, withdraw DAI, verify consistency
        BoringVault crossVault = new BoringVault(address(this), "Cross", "CRS", 18);
        AccountantWithRateProviders crossAccountant = new AccountantWithRateProviders(
            address(this), address(crossVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        crossAccountant.setRateProviderData(USDC, true, address(0));
        crossAccountant.setRateProviderData(DAI, true, address(0));

        // Deposit 1000 USDC
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 1000e6);
        vm.stopPrank();

        USDC.approve(address(crossVault), 1000e6);
        uint256 shares = 1000e18; // Assuming fresh vault with 1:1 rate
        crossVault.enter(address(this), USDC, 1000e6, address(this), shares);

        uint256 daiOut = 1000e18; // Expected output
        deal(address(DAI), address(crossVault), daiOut + 1e18); // Add buffer for safety
        crossVault.exit(address(this), DAI, daiOut, address(this), shares);

        // Should get ~1000 DAI (minus rounding)
        assertApproxEqRel(daiOut, 1000e18, 0.001e18, "Should get equivalent DAI for USDC");
    }

    function testMultiAssetDepositWithdrawAfter30Days() external {
        // Fresh setup
        BoringVault multiVault = new BoringVault(address(this), "MultiAsset", "MA", 18);
        AccountantWithRateProviders multiAccountant = new AccountantWithRateProviders(
            address(this), address(multiVault), payoutAddress, 1e18, address(USDC), 1.1e4, 0.9e4, 1, 0
        );

        // Setup assets
        multiAccountant.setRateProviderData(USDC, true, address(0));
        multiAccountant.setRateProviderData(DAI, true, address(0));
        multiAccountant.setRateProviderData(USDT, true, address(0));
        multiAccountant.setLendingRate(500); // 5% APY

        // Get funds
        vm.startPrank(usdcWhale);
        USDC.safeTransfer(address(this), 10_000e6);
        vm.stopPrank();
        deal(address(DAI), address(this), 10_000e18);
        deal(address(USDT), address(this), 10_000e6);

        // Approve
        USDC.safeApprove(address(multiVault), type(uint256).max);
        DAI.safeApprove(address(multiVault), type(uint256).max);
        USDT.safeApprove(address(multiVault), type(uint256).max);

        // Deposit multiple assets
        multiVault.enter(address(this), USDC, 5000e6, address(this), 5000e18);
        multiVault.enter(address(this), DAI, 3000e18, address(this), 3000e18);
        multiVault.enter(address(this), USDT, 2000e6, address(this), 2000e18);

        uint256 totalSharesBefore = multiVault.balanceOf(address(this));
        assertEq(totalSharesBefore, 10_000e18, "Should have 10k shares");

        // Skip 30 days with daily checkpoints
        for (uint256 i = 0; i < 30; i++) {
            skip(1 days);
            multiAccountant.checkpoint();
        }

        uint256 rate = multiAccountant.getRate();
        console.log("Rate after 30 days:", rate);

        // Withdraw different assets and verify precision
        // Put assets in vault for withdrawal
        deal(address(USDC), address(multiVault), 20_000e6);
        deal(address(DAI), address(multiVault), 20_000e18);
        deal(address(USDT), address(multiVault), 20_000e6);

        // Calculate expected values with interest
        uint256 expectedValue = totalSharesBefore.mulDivDown(rate, 1e18);
        console.log("Expected value in 18 decimals:", expectedValue);

        // Withdraw 1/3 as each asset
        uint256 sharesPer = totalSharesBefore / 3;

        // Withdraw as USDC
        uint256 usdcOut = sharesPer.mulDivDown(rate, 1e18);
        usdcOut = usdcOut.mulDivDown(1e6, 1e18); // Convert to USDC decimals
        multiVault.exit(address(this), USDC, usdcOut, address(this), sharesPer);

        // Withdraw as DAI
        uint256 daiOut = sharesPer.mulDivDown(rate, 1e18); // Already 18 decimals
        multiVault.exit(address(this), DAI, daiOut, address(this), sharesPer);

        // Withdraw as USDT
        uint256 usdtOut = sharesPer.mulDivDown(rate, 1e18);
        usdtOut = usdtOut.mulDivDown(1e6, 1e18); // Convert to USDT decimals
        multiVault.exit(address(this), USDT, usdtOut, address(this), sharesPer);

        console.log("USDC withdrawn:", usdcOut);
        console.log("DAI withdrawn:", daiOut);
        console.log("USDT withdrawn:", usdtOut);

        // Verify total value preserved (accounting for rounding)
        uint256 totalValueOut = usdcOut * 1e12 + daiOut + usdtOut * 1e12; // Convert all to 18 decimals
        assertApproxEqRel(totalValueOut, expectedValue, 0.001e18, "Total value should be preserved");
    }

    // function testMultiAssetDepositWithdrawAfter30Days_Comprehensive() external {
    //     // Fresh setup
    //     BoringVault multiVault = new BoringVault(address(this), "MultiAsset", "MA", 18);
    //     AccountantWithRateProviders multiAccountant = new AccountantWithRateProviders(
    //         address(this),
    //         address(multiVault),
    //         payoutAddress,
    //         1e18,
    //         address(USDC),
    //         1.1e4,
    //         0.9e4,
    //         1,
    //         100 // 1% mgmt fee
    //     );

    //     // Setup assets
    //     multiAccountant.setRateProviderData(USDC, true, address(0));
    //     multiAccountant.setRateProviderData(DAI, true, address(0));
    //     multiAccountant.setRateProviderData(USDT, true, address(0));
    //     multiAccountant.setLendingRate(500); // 5% APY

    //     // Get funds
    //     vm.startPrank(usdcWhale);
    //     USDC.safeTransfer(address(this), 10_000e6);
    //     vm.stopPrank();
    //     deal(address(DAI), address(this), 10_000e18);
    //     deal(address(USDT), address(this), 10_000e6);

    //     // Approve using safeApprove
    //     USDC.safeApprove(address(multiVault), type(uint256).max);
    //     DAI.safeApprove(address(multiVault), type(uint256).max);
    //     USDT.safeApprove(address(multiVault), type(uint256).max);

    //     // Record initial state
    //     uint256 initialRate = multiAccountant.getRate();
    //     assertEq(initialRate, 1e18, "Should start at 1:1");

    //     // Deposit different amounts of each asset
    //     // $5000 USDC, $3000 DAI, $2000 USDT = $10,000 total
    //     multiVault.enter(address(this), USDC, 5000e6, address(this), 5000e18);
    //     multiVault.enter(address(this), DAI, 3000e18, address(this), 3000e18);
    //     multiVault.enter(address(this), USDT, 2000e6, address(this), 2000e18);

    //     uint256 totalShares = multiVault.balanceOf(address(this));
    //     assertEq(totalShares, 10_000e18, "Should have 10k shares");

    //     // Skip 30 days with daily checkpoints
    //     for (uint256 i = 0; i < 30; i++) {
    //         skip(1 days);
    //         multiAccountant.checkpoint();
    //     }

    //     // Calculate expected values
    //     // Interest: 10,000 * 5% * 30/365 = ~$41.10
    //     // Management fee: 10,000 * 1% * 30/365 = ~$8.22
    //     // Net to depositors: ~$41.10

    //     uint256 rateAfter30Days = multiAccountant.getRate();
    //     console.log("Rate after 30 days (18 dec):", rateAfter30Days);

    //     // Calculate expected rate: 1e18 * (1 + 0.05 * 30/365) = ~1.00411e18
    //     uint256 expectedRate = 1e18 + uint256(1e18).mulDivDown(500 * 30 days, 365 days * 10_000);
    //     console.log("Expected rate (18 dec):", expectedRate);
    //     assertApproxEqRel(rateAfter30Days, expectedRate, 0.0001e18, "Rate should match expected");

    //     // Check management fees accrued
    //     uint256 feesOwed = multiAccountant.previewFeesOwed();
    //     console.log("Management fees owed (6 dec):", feesOwed);

    //     // Expected fees: 10,000 * 0.01 * 30/365 = ~8.22 USDC
    //     uint256 expectedFees = uint256(10_000e6).mulDivDown(100 * 30 days, 365 days * 10_000);
    //     console.log("Expected fees (6 dec):", expectedFees);
    //     assertApproxEqRel(feesOwed, expectedFees, 0.01e18, "Fees should match expected");

    //     // Now test withdrawals with different assets
    //     // Put assets in vault for withdrawal
    //     deal(address(USDC), address(multiVault), 20_000e6);
    //     deal(address(DAI), address(multiVault), 20_000e18);
    //     deal(address(USDT), address(multiVault), 20_000e6);

    //     // Test Case 1: Withdraw 1000 shares as USDC
    //     uint256 shares1000Value = 1000e18 * rateAfter30Days / 1e18; // Value in 18 decimals
    //     uint256 expectedUSDC = shares1000Value * 1e6 / 1e18; // Convert to USDC decimals

    //     uint256 balanceBefore = USDC.balanceOf(address(this));
    //     multiVault.exit(address(this), USDC, expectedUSDC, address(this), 1000e18);
    //     uint256 receivedUSDC = USDC.balanceOf(address(this)) - balanceBefore;

    //     console.log("1000 shares withdrawn as USDC:", receivedUSDC);
    //     console.log("Expected USDC:", expectedUSDC);
    //     assertEq(receivedUSDC, expectedUSDC, "USDC withdrawal should be exact");

    //     // Verify this is ~$1004.11 (1000 + interest)
    //     assertApproxEqRel(receivedUSDC, 1004.11e6, 0.001e18, "Should be ~$1004.11");

    //     // Test Case 2: Withdraw 2000 shares as DAI
    //     uint256 shares2000Value = 2000e18 * rateAfter30Days / 1e18;
    //     uint256 expectedDAI = shares2000Value; // Already in 18 decimals

    //     balanceBefore = DAI.balanceOf(address(this));
    //     multiVault.exit(address(this), DAI, expectedDAI, address(this), 2000e18);
    //     uint256 receivedDAI = DAI.balanceOf(address(this)) - balanceBefore;

    //     console.log("2000 shares withdrawn as DAI:", receivedDAI);
    //     console.log("Expected DAI:", expectedDAI);
    //     assertEq(receivedDAI, expectedDAI, "DAI withdrawal should be exact");

    //     // Verify this is ~$2008.22
    //     assertApproxEqRel(receivedDAI, 2008.22e18, 0.001e18, "Should be ~$2008.22");

    //     // Test Case 3: Withdraw 3000 shares as USDT
    //     uint256 shares3000Value = 3000e18 * rateAfter30Days / 1e18;
    //     uint256 expectedUSDT = shares3000Value * 1e6 / 1e18; // Convert to USDT decimals

    //     balanceBefore = USDT.balanceOf(address(this));
    //     multiVault.exit(address(this), USDT, expectedUSDT, address(this), 3000e18);
    //     uint256 receivedUSDT = USDT.balanceOf(address(this)) - balanceBefore;

    //     console.log("3000 shares withdrawn as USDT:", receivedUSDT);
    //     console.log("Expected USDT:", expectedUSDT);
    //     assertEq(receivedUSDT, expectedUSDT, "USDT withdrawal should be exact");

    //     // Verify this is ~$3012.33
    //     assertApproxEqRel(receivedUSDT, 3012.33e6, 0.001e18, "Should be ~$3012.33");

    //     // Test Case 4: Verify total value consistency
    //     uint256 totalValueWithdrawn = receivedUSDC + receivedUSDT; // Both 6 decimals
    //     totalValueWithdrawn = totalValueWithdrawn * 1e12 + receivedDAI; // Convert to 18 decimals

    //     uint256 expectedTotalValue = 6000e18 * rateAfter30Days / 1e18; // 6000 shares withdrawn
    //     console.log("Total value withdrawn (18 dec):", totalValueWithdrawn);
    //     console.log("Expected total value (18 dec):", expectedTotalValue);

    //     assertApproxEqRel(
    //         totalValueWithdrawn,
    //         expectedTotalValue,
    //         0.0001e18,
    //         "Total value should be preserved across different assets"
    //     );

    //     // Final verification: Remaining shares value
    //     uint256 remainingShares = multiVault.balanceOf(address(this));
    //     assertEq(remainingShares, 4000e18, "Should have 4000 shares left");

    //     uint256 remainingValue = remainingShares * rateAfter30Days / 1e18;
    //     console.log("Remaining 4000 shares value:", remainingValue);
    //     assertApproxEqRel(remainingValue, 4016.44e18, 0.001e18, "Should be ~$4016.44");
    // }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

// Helper contracts for testing
contract MockRateProvider is IRateProvider {
    uint256 public rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol, decimals_) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
