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
import { GenericRateProvider } from "src/helper/GenericRateProvider.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract AccountantWithRateProvidersTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7_777_777);
    RolesAuthority public rolesAuthority;
    GenericRateProvider public mETHRateProvider;
    GenericRateProvider public ptRateProvider;

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant ADMIN_ROLE = 2;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 3;
    uint8 public constant BORING_VAULT_ROLE = 4;
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant BASIS_POINTS = 10_000;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19_827_152;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        accountant.setAuthority(rolesAuthority);
        boringVault.setAuthority(rolesAuthority);

        // Setup roles authority.
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.pause.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.unpause.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateDelay.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateUpper.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateLower.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.setManagementFeeRate.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updatePayoutAddress.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.setRateProviderData.selector, true
        );
        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE,
            address(accountant),
            AccountantWithRateProviders.updateExchangeRate.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            BORING_VAULT_ROLE, address(accountant), AccountantWithRateProviders.claimFees.selector, true
        );

        // Allow the boring vault to receive ETH.
        rolesAuthority.setPublicCapability(address(boringVault), bytes4(0), true);

        rolesAuthority.setUserRole(address(this), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(this), UPDATE_EXCHANGE_RATE_ROLE, true);
        rolesAuthority.setUserRole(address(boringVault), BORING_VAULT_ROLE, true);
        deal(address(WETH), address(this), 1000e18);
        WETH.safeApprove(address(boringVault), 1000e18);
        boringVault.enter(address(this), WETH, 1000e18, address(address(this)), 1000e18);

        accountant.setRateProviderData(EETH, true, address(0));
        accountant.setRateProviderData(WEETH, false, address(WEETH_RATE_PROVIDER));
    }

    function testEdgeScenario() external {
        console.log("=== TEST: edge scenario - 10% APR with Fee Claim ===");

        // Setup: 10% APR lending, 10% management fee (as mentioned in the chat)
        uint256 lendingRate = 1000; // 10% APR
        uint256 managementFeeRate = 1000; // 10% management fee

        accountant.setLendingRate(lendingRate);
        accountant.setManagementFeeRate(uint16(managementFeeRate));

        // Initial deposit: 999.2605472 shares
        uint256 initialShares = 999_260_547_200_000_000_000; // 999.2605472e18

        console.log("Initial Setup: 999.26 shares at rate 1.0");
        uint256 initialRate = accountant.getRate();
        assertEq(initialRate, 1e18, "Initial rate should be 1.0");

        // Simulate time passing: 1.43625 days (124092 seconds)
        uint256 timeElapsed = 124_092;
        skip(timeElapsed);

        console.log("After 124092 seconds (1.43625 days):");

        // Check rate BEFORE any operations (view only)
        (uint96 rateBeforeClaim, uint256 interestAccruedBefore) = accountant.calculateExchangeRateWithInterest();
        uint256 valueBeforeClaim = initialShares.mulDivDown(rateBeforeClaim, 1e18);

        // Expected value from Excel: 1000.3934931506800 (simple interest)
        uint256 expectedSimpleInterest =
            initialShares + initialShares.mulDivDown(lendingRate * timeElapsed, SECONDS_PER_YEAR * BASIS_POINTS);

        // Verify the rate has increased as expected
        assertGt(rateBeforeClaim, 1e18, "Rate should have increased");
        assertApproxEqRel(
            valueBeforeClaim, expectedSimpleInterest, 0.001e18, "Value before claim should match expected"
        );

        console.log("  Rate increased as expected");
        console.log("  Interest accrued correctly");

        // Get fees to claim
        uint256 feesToClaim = accountant.previewFeesOwed();
        assertGt(feesToClaim, 0, "Should have fees to claim");

        console.log("Claiming fees...");

        // Setup vault for fee claim
        deal(address(WETH), address(boringVault), feesToClaim);
        vm.startPrank(address(boringVault));
        WETH.approve(address(accountant), feesToClaim);

        // Get rate before claim
        uint256 storedRateBefore = accountant.getRate();

        // CLAIM FEES - This is where Varinder saw the rate drop
        accountant.claimFees(WETH);
        vm.stopPrank();

        // Check rate AFTER claim
        (uint96 rateAfterClaim, uint256 interestAccruedAfter) = accountant.calculateExchangeRateWithInterest();
        uint256 valueAfterClaim = initialShares.mulDivDown(rateAfterClaim, 1e18);

        console.log("After Fee Claim:");

        // The critical assertion - rate should NEVER decrease
        assertGe(rateAfterClaim, storedRateBefore, "CRITICAL: Rate decreased after fee claim!");

        if (rateAfterClaim < storedRateBefore) {
            console.log("  ERROR: RATE DROPPED!");
            revert("Rate dropped after fee claim - this is the bug!");
        } else if (rateAfterClaim > storedRateBefore) {
            console.log("  Rate increased (expected with time passage)");
        } else {
            console.log("  Rate unchanged (expected if no time passed)");
        }

        // Verify stored rate
        (,,, uint96 storedRate,,,,,,) = accountant.accountantState();
        assertEq(storedRate, rateAfterClaim, "Stored rate should match calculated rate");

        // Verify interest accrued dropped to near zero (timer reset)
        assertLt(interestAccruedAfter, interestAccruedBefore, "Interest accrued should reset after claim");

        // Verify the value is still correct
        assertApproxEqRel(
            valueAfterClaim, expectedSimpleInterest, 0.001e18, "Value after claim should still match expected"
        );

        console.log("Test passed: Rate never decreased, value preserved");
    }

    function testReproduceRateDrop() external {
        console.log("=== TEST: Reproduce Rate Drop Issue (Pre-Fix) ===");

        // Setup
        accountant.setLendingRate(1000); // 10% APR
        accountant.setManagementFeeRate(1000); // 10% management

        uint256 shares = 1000e18;
        console.log("Initial: 1000 shares at rate 1.0");

        // Time passes WITHOUT checkpointing (old behavior)
        skip(11 hours);

        // Check calculated vs stored rate
        (uint96 calculatedRate,) = accountant.calculateExchangeRateWithInterest();
        (,,, uint96 storedRateBefore,,,,,,) = accountant.accountantState();

        console.log("After 11 hours (no checkpoint):");
        assertGt(calculatedRate, storedRateBefore, "Calculated should be > stored without checkpoint");

        // Trigger checkpoint
        accountant.setLendingRate(1000);

        (,,, uint96 storedRateAfter,,,,,,) = accountant.accountantState();
        console.log("After checkpoint via setLendingRate:");
        assertEq(storedRateAfter, calculatedRate, "Stored should now equal calculated");

        // More time passes
        skip(1 hours);

        // Claim fees
        uint256 fees = accountant.previewFeesOwed();
        deal(address(WETH), address(boringVault), fees);

        vm.startPrank(address(boringVault));
        WETH.approve(address(accountant), fees);

        uint256 rateBeforeClaim = accountant.getRate();
        accountant.claimFees(WETH);
        uint256 rateAfterClaim = accountant.getRate();

        vm.stopPrank();

        console.log("After fee claim:");

        // Critical check
        if (rateAfterClaim < rateBeforeClaim) {
            console.log("  BUG DETECTED: Rate dropped!");
            revert("Rate drop detected - this should not happen with fix");
        } else {
            console.log("  PASS: Rate maintained or increased");
        }

        assertGe(rateAfterClaim, rateBeforeClaim, "Rate should never decrease");

        console.log("Test completed successfully");
    }

    function testPause() external {
        accountant.pause();

        (,,,,,,, bool is_paused,,) = accountant.accountantState();
        assertTrue(is_paused == true, "Accountant should be paused");

        accountant.unpause();

        (,,,,,,, is_paused,,) = accountant.accountantState();

        assertTrue(is_paused == false, "Accountant should be unpaused");
    }

    function testUpdateDelay() external {
        accountant.updateDelay(2);

        (,,,,,,,, uint32 delay_in_seconds,) = accountant.accountantState();

        assertEq(delay_in_seconds, 2, "Delay should be 2 seconds");
    }

    function testUpdateUpper() external {
        accountant.updateUpper(1.002e4);
        (,,,, uint16 upper_bound,,,,,) = accountant.accountantState();

        assertEq(upper_bound, 1.002e4, "Upper bound should be 1.002e4");
    }

    function testUpdateLower() external {
        accountant.updateLower(0.998e4);
        (,,,,, uint16 lower_bound,,,,) = accountant.accountantState();

        assertEq(lower_bound, 0.998e4, "Lower bound should be 0.9980e4");
    }

    function testsetManagementFeeRate() external {
        accountant.setManagementFeeRate(0.09e4);
        (,,,,,,,,, uint16 management_fee) = accountant.accountantState();

        assertEq(management_fee, 0.09e4, "Management Fee should be 0.09e4");
    }

    function testUpdatePayoutAddress() external {
        (address payout,,,,,,,,,) = accountant.accountantState();
        assertEq(payout, payout_address, "Payout address should be the same");

        address new_payout_address = vm.addr(8_888_888);
        accountant.updatePayoutAddress(new_payout_address);

        (payout,,,,,,,,,) = accountant.accountantState();
        assertEq(payout, new_payout_address, "Payout address should be the same");
    }

    function testUpdateRateProvider() external {
        (bool is_pegged_to_base, IRateProvider rate_provider) = accountant.rateProviderData(WEETH);
        assertTrue(is_pegged_to_base == false, "WEETH should not be pegged to base");
        assertEq(address(rate_provider), WEETH_RATE_PROVIDER, "WEETH rate provider should be set");
    }

    function testUpdateExchangeRateAndFeeLogic() external {
        accountant.setManagementFeeRate(0.01e4); // 1% management fee
        uint256 testStartTime = block.timestamp;
        uint256 avgAUM = 1000e18; // Initial deposit

        // Update 1: After 1 hour
        skip(1 days / 24);
        uint96 new_exchange_rate = uint96(1.0005e18);
        accountant.updateExchangeRate(new_exchange_rate);

        // Calculate expected fees
        uint256 totalTimeElapsed = block.timestamp - testStartTime;
        uint256 expected_fees_owed = avgAUM.mulDivDown(uint256(0.01e4) * totalTimeElapsed, 365 days * 10_000);

        (
            ,
            uint128 fees_owed,
            uint128 total_shares,
            uint96 current_exchange_rate,
            ,
            ,
            uint64 last_update_timestamp,
            bool is_paused,
            ,
        ) = accountant.accountantState();

        assertApproxEqRel(fees_owed, expected_fees_owed, 0.001e18, "Fees after 1 hour");
        assertEq(total_shares, 1000e18, "Total shares should be 1_000e18");
        assertEq(current_exchange_rate, new_exchange_rate, "Current exchange rate should be updated");
        assertEq(last_update_timestamp, uint64(block.timestamp), "Last update timestamp should be updated");
        assertFalse(is_paused, "Accountant should not be paused");

        // Update 2: After another hour (2 hours total)
        skip(1 days / 24);
        new_exchange_rate = uint96(1.001e18);
        accountant.updateExchangeRate(new_exchange_rate);

        totalTimeElapsed = block.timestamp - testStartTime;
        expected_fees_owed = avgAUM.mulDivDown(uint256(0.01e4) * totalTimeElapsed, 365 days * 10_000);

        (, fees_owed, total_shares, current_exchange_rate,,, last_update_timestamp, is_paused,,) =
            accountant.accountantState();

        assertApproxEqRel(fees_owed, expected_fees_owed, 0.001e18, "Fees after 2 hours");
        assertEq(current_exchange_rate, new_exchange_rate, "Rate should update");
        assertFalse(is_paused, "Should not be paused");

        // Update 3: After another hour (3 hours total)
        skip(1 days / 24);
        new_exchange_rate = uint96(1.0005e18);
        accountant.updateExchangeRate(new_exchange_rate);

        totalTimeElapsed = block.timestamp - testStartTime;
        expected_fees_owed = avgAUM.mulDivDown(uint256(0.01e4) * totalTimeElapsed, 365 days * 10_000);

        (, fees_owed,,,,,, is_paused,,) = accountant.accountantState();
        assertApproxEqRel(fees_owed, expected_fees_owed, 0.001e18, "Fees after 3 hours");
        assertFalse(is_paused, "Should not be paused");

        // Test pausing due to timing: Update too quickly
        new_exchange_rate = uint96(1.0e18);
        accountant.updateExchangeRate(new_exchange_rate);

        // No time has passed, so expected fees remain the same
        (, fees_owed,, current_exchange_rate,,, last_update_timestamp, is_paused,,) = accountant.accountantState();

        assertApproxEqRel(fees_owed, expected_fees_owed, 0.001e18, "Fees should not change on pause");
        assertEq(current_exchange_rate, new_exchange_rate, "Rate should still update even when pausing");
        assertTrue(is_paused, "Should pause due to timing violation");

        // Unpause for next test
        accountant.unpause();

        // Test pausing due to bounds: After 1 more hour (4 hours total)
        skip(1 days / 24);

        // Recalculate expected fees after skip
        totalTimeElapsed = block.timestamp - testStartTime;
        expected_fees_owed = avgAUM.mulDivDown(uint256(0.01e4) * totalTimeElapsed, 365 days * 10_000);

        new_exchange_rate = uint96(10.0e18); // Way out of bounds
        accountant.updateExchangeRate(new_exchange_rate);

        (, fees_owed,, current_exchange_rate,,, last_update_timestamp, is_paused,,) = accountant.accountantState();

        assertApproxEqRel(fees_owed, expected_fees_owed, 0.001e18, "Fees after 4 hours");
        assertEq(current_exchange_rate, new_exchange_rate, "Rate should update even when pausing");
        assertTrue(is_paused, "Should pause due to bounds violation");
    }

    function testClaimFees() external {
        accountant.setManagementFeeRate(0.01e4);

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        uint96 new_exchange_rate = uint96(1.0005e18);
        accountant.updateExchangeRate(new_exchange_rate);

        (, uint128 fees_owed,,,,,,,,) = accountant.accountantState();
        // assertEq(fees_owed, 0, "Fees owed should be 0");

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        new_exchange_rate = uint96(1.001e18);
        accountant.updateExchangeRate(new_exchange_rate);

        // uint256 expected_fees_owed =
        //     uint256(0.01e4).mulDivDown(uint256(1 days / 24).mulDivDown(1000.5e18, 365 days), 1e4);

        // (, fees_owed,,,,,,,,) = accountant.accountantState();
        // assertEq(fees_owed, expected_fees_owed, "Fees owed should equal expected");
        // Before claiming fees, ensure vault has enough WETH
        uint256 actualFeesToClaim = accountant.previewFeesOwed();
        deal(address(WETH), address(boringVault), actualFeesToClaim);

        vm.startPrank(address(boringVault));
        WETH.safeApprove(address(accountant), actualFeesToClaim);
        accountant.claimFees(WETH);
        vm.stopPrank();

        assertEq(WETH.balanceOf(payout_address), actualFeesToClaim, "Payout address should have received fees");

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        new_exchange_rate = uint96(1.0015e18);
        accountant.updateExchangeRate(new_exchange_rate);

        deal(address(WEETH), address(boringVault), 1e18);
        vm.startPrank(address(boringVault));
        WEETH.safeApprove(address(accountant), 1e18);
        accountant.claimFees(WEETH);
        vm.stopPrank();
    }

    function testRates() external {
        // getRate and getRate in quote should work.
        uint256 rate = accountant.getRate();
        uint256 expected_rate = 1e18;
        assertEq(rate, expected_rate, "Rate should be expected rate");
        rate = accountant.getRateSafe();
        assertEq(rate, expected_rate, "Rate should be expected rate");

        uint256 rate_in_quote = accountant.getRateInQuote(WEETH);
        expected_rate = uint256(1e18).mulDivDown(1e18, IRateProvider(address(WEETH_RATE_PROVIDER)).getRate());
        assertEq(rate_in_quote, expected_rate, "Rate should be expected rate");
        rate_in_quote = accountant.getRateInQuoteSafe(WEETH);
        assertEq(rate_in_quote, expected_rate, "Rate should be expected rate");
    }

    function testMETHRateProvider() external {
        // Deploy GenericRateProvider for mETH.
        bytes4 selector = bytes4(keccak256(abi.encodePacked("mETHToETH(uint256)")));
        uint256 amount = 1e18;
        mETHRateProvider = new GenericRateProvider(mantleLspStaking, selector, bytes32(amount), 0, 0, 0, 0, 0, 0, 0);

        uint256 expectedRate = MantleLspStaking(mantleLspStaking).mETHToETH(1e18);
        uint256 gas = gasleft();
        uint256 rate = mETHRateProvider.getRate();
        console.log("Gas used: ", gas - gasleft());

        assertEq(rate, expectedRate, "Rate should be expected rate");

        // Setup rate in accountant.
        accountant.setRateProviderData(METH, false, address(mETHRateProvider));

        uint256 expectedRateInMeth = accountant.getRate().mulDivDown(1e18, rate);

        uint256 rateInMeth = accountant.getRateInQuote(METH);

        assertEq(rateInMeth, expectedRateInMeth, "Rate should be expected rate");

        assertLt(rateInMeth, 1e18, "Rate should be less than 1e18");
    }

    function testPtRateProvider() external {
        // Deploy GenericRateProvider for mETH.
        bytes4 selector = bytes4(keccak256(abi.encodePacked("getValue(address,uint256,address)")));
        uint256 amount = 1e18;
        bytes32 pt = 0x000000000000000000000000c69Ad9baB1dEE23F4605a82b3354F8E40d1E5966; // pendleEethPt
        bytes32 quote = 0x000000000000000000000000C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // wETH
        ptRateProvider =
            new GenericRateProvider(liquidV1PriceRouter, selector, pt, bytes32(amount), quote, 0, 0, 0, 0, 0);

        uint256 expectedRate = PriceRouter(liquidV1PriceRouter).getValue(pendleEethPt, 1e18, address(WETH));
        uint256 rate = ptRateProvider.getRate();

        assertEq(rate, expectedRate, "Rate should be expected rate");

        // Setup rate in accountant.
        accountant.setRateProviderData(ERC20(pendleEethPt), false, address(ptRateProvider));

        uint256 expectedRateInPt = accountant.getRate().mulDivDown(1e18, rate);

        uint256 rateInPt = accountant.getRateInQuote(ERC20(pendleEethPt));

        assertEq(rateInPt, expectedRateInPt, "Rate should be expected rate");

        assertGt(rateInPt, 1e18, "Rate should be greater than 1e18");
    }

    function testReverts() external {
        accountant.pause();

        accountant.updateExchangeRate(0);

        address attacker = vm.addr(1);
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccountantWithRateProviders.AccountantWithRateProviders__OnlyCallableByBoringVault.selector
            )
        );
        accountant.claimFees(WETH);
        vm.stopPrank();

        vm.startPrank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__Paused.selector)
        );
        accountant.claimFees(WETH);
        vm.stopPrank();

        accountant.unpause();

        vm.startPrank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__ZeroFeesOwed.selector)
        );
        accountant.claimFees(WETH);
        vm.stopPrank();

        // Trying to claimFees with unsupported token should revert.
        vm.startPrank(address(boringVault));
        vm.expectRevert();
        accountant.claimFees(ETHX);
        vm.stopPrank();

        accountant.pause();

        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__Paused.selector)
        );
        accountant.getRateSafe();

        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__Paused.selector)
        );
        accountant.getRateInQuoteSafe(WEETH);

        // Trying to getRateInQuote with unsupported token should revert.
        vm.expectRevert();
        accountant.getRateInQuoteSafe(ETHX);

        // Updating bounds, and management fee reverts.
        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__UpperBoundTooSmall.selector)
        );
        accountant.updateUpper(0.9999e4);

        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__LowerBoundTooLarge.selector)
        );
        accountant.updateLower(1.0001e4);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccountantWithRateProviders.AccountantWithRateProviders__ManagementFeeTooLarge.selector
            )
        );
        accountant.setManagementFeeRate(0.2001e4);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccountantWithRateProviders.AccountantWithRateProviders__UpdateDelayTooLarge.selector
            )
        );
        accountant.updateDelay(14 days + 1);
    }

    function testLendingRateAndProtocolFee() external {
        console.log("\n=== TEST: Lending Rate and Protocol Fee ===");

        // Set lending and protocol fee rates
        uint256 lendingRate = 1000; // 10% APY
        uint16 managementFeeRate = 200; // 2% APY

        accountant.setLendingRate(lendingRate);
        accountant.setManagementFeeRate(managementFeeRate);

        // Verify borrower rate
        uint256 borrowerRate = accountant.getBorrowerRate();
        assertEq(borrowerRate, 1200, "Borrower rate should be 12%");
        console.log("   Lending Rate: %s bps", lendingRate);
        console.log("   Protocol Fee Rate: %s bps", managementFeeRate);
        console.log("   Total Borrower Rate: %s bps", borrowerRate);

        // Test interest accrual
        skip(365 days); // Skip 1 year

        (uint96 newRate,) = accountant.calculateExchangeRateWithInterest();
        uint256 expectedRate = uint256(1e18).mulDivDown(11_000, 10_000); // 1.1x
        assertApproxEqRel(newRate, expectedRate, 0.01e18, "Exchange rate should increase by 10%");
        console.log("   Exchange rate after 1 year: %s", newRate);

        // Check protocol fees accumulated
        uint256 previewFees = accountant.previewFeesOwed();
        // Management fee is 2% of FINAL value (1000 * 1.1 = 1100)
        uint256 expectedFees = uint256(1100e18).mulDivDown(200, 10_000); // 2% of 1100
        assertApproxEqRel(previewFees, expectedFees, 0.01e18, "Protocol fees should be 2% of total value");
        console.log("   Protocol fees owed: %s", previewFees);
    }

    function testMaxLendingRateEnforcement() external {
        console.log("\n=== TEST: Max Lending Rate Enforcement ===");

        // Set max rate
        uint256 maxRate = 3000; // 30%
        accountant.setMaxLendingRate(maxRate);

        // Try to set rate above max
        vm.expectRevert("Lending rate exceeds maximum");
        accountant.setLendingRate(3100);
        console.log("   Setting rate above max correctly reverted");

        // Set rate at max should work
        accountant.setLendingRate(3000);
        (uint256 currentLendingRate,) = accountant.lendingInfo();
        assertEq(currentLendingRate, 3000);
        console.log("   Setting rate at max successful");
    }

    function testLendingWithProtocolFeeFlow() external {
        console.log("\n=== TEST: Complete Lending Flow with Protocol Fees ===");

        // Setup rates
        accountant.setLendingRate(1000); // 10% lending
        accountant.setManagementFeeRate(200); // 2% protocol fee

        uint256 initialDeposits = WETH.balanceOf(address(boringVault));
        console.log("   Initial vault balance: %s WETH", initialDeposits / 1e18);

        // Simulate time passing
        skip(182.5 days); // 6 months

        // Update exchange rate to checkpoint
        (uint96 currentRate,) = accountant.calculateExchangeRateWithInterest();
        accountant.updateExchangeRate(currentRate);

        // Check accumulated fees
        (, uint128 feesOwed,,,,,,,,) = accountant.accountantState();
        console.log("   Protocol fees after 6 months: %s WETH", feesOwed / 1e18);

        // Vault value should increase by lending rate only
        uint256 vaultValue = boringVault.totalSupply().mulDivDown(currentRate, 1e18);
        uint256 expectedValue = initialDeposits.mulDivDown(10_500, 10_000); // 5% for 6 months
        assertApproxEqRel(vaultValue, expectedValue, 0.01e18);
        console.log("   Vault value increased to: %s WETH", vaultValue / 1e18);

        // Claim protocol fees
        deal(address(WETH), address(boringVault), feesOwed); // Ensure vault has fees
        vm.startPrank(address(boringVault));
        WETH.approve(address(accountant), feesOwed);
        accountant.claimFees(WETH);
        vm.stopPrank();

        assertGt(WETH.balanceOf(payout_address), 0, "Payout address should receive fees");
        console.log("   Protocol fees claimed: %s WETH", WETH.balanceOf(payout_address) / 1e18);
    }

    function testRateChangeCheckpointing() external {
        console.log("\n=== TEST: Rate Change Checkpointing ===");

        // Set initial rates
        accountant.setLendingRate(1000);
        accountant.setManagementFeeRate(100);

        // Let time pass
        skip(30 days);

        // Get current accumulated interest
        (uint96 rateBefore,) = accountant.calculateExchangeRateWithInterest();
        uint256 feesBefore = accountant.previewFeesOwed();

        console.log("   Rate before change: %s", rateBefore);
        console.log("   Fees before change: %s", feesBefore);

        // Change lending rate (should checkpoint)
        accountant.setLendingRate(2000);

        // Verify checkpoint happened
        (, uint128 feesOwed,, uint96 exchangeRate,,,,,,) = accountant.accountantState();
        assertEq(exchangeRate, rateBefore, "Exchange rate should be checkpointed");
        assertEq(feesOwed, feesBefore, "Fees should be checkpointed");

        console.log("   Checkpoint successful on rate change");
    }

    function testInterestAccrualMathPrecision() external {
        console.log("\n=== TEST: Interest Accrual Math Precision ===");

        // Setup: 10% APY lending rate
        uint256 lendingRate = 1000; // 10% in basis points
        accountant.setLendingRate(lendingRate);

        uint256 principal = 1000e18;
        uint256 initialRate = accountant.getRate();
        assertEq(initialRate, 1e18, "Initial rate should be 1:1");

        // Test 1: Daily accrual precision
        console.log("\n1. DAILY ACCRUAL TEST");

        // Save current state and timestamp
        uint256 checkpointTime = block.timestamp;

        for (uint256 day = 1; day <= 7; day++) {
            skip(1 days);
            (uint96 currentRate,) = accountant.calculateExchangeRateWithInterest();

            // Contract uses simple interest
            uint256 expectedRate = 1e18 + (1e18 * lendingRate * day * 1 days) / (10_000 * 365 days);

            console.log("   Day %d - Rate: %d, Expected: %d", day, currentRate, expectedRate);
            assertApproxEqRel(currentRate, expectedRate, 0.00001e18, "Daily simple interest accuracy");
        }

        // Test 2: Annual calculation
        console.log("\n2. ANNUAL ACCRUAL TEST");

        // Create a fresh accountant for clean test
        AccountantWithRateProviders freshAccountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );
        rolesAuthority.setUserRole(address(freshAccountant), UPDATE_EXCHANGE_RATE_ROLE, true);
        freshAccountant.setLendingRate(lendingRate);

        skip(365 days);

        (uint96 annualRate,) = freshAccountant.calculateExchangeRateWithInterest();
        uint256 expectedAnnualRate = 1.1e18; // 10% increase with simple interest

        console.log("   After 1 year - Rate: %d", annualRate);
        console.log("   Expected: %d", expectedAnnualRate);

        assertEq(annualRate, expectedAnnualRate, "Annual rate should be exactly 1.1x");
    }

    function testCheckpointingAccuracy() external {
        console.log("\n=== TEST: Checkpointing Accuracy ===");

        // Setup rates
        accountant.setLendingRate(2000); // 20% APY
        accountant.setManagementFeeRate(500); // 5% APY

        uint256 checkpointGas;
        uint256 lastRate = 1e18;

        // Test multiple checkpoints
        for (uint256 i = 1; i <= 4; i++) {
            skip(90 days); // Quarterly

            // Get rate before checkpoint
            (uint96 rateBeforeCheckpoint,) = accountant.calculateExchangeRateWithInterest();
            uint256 feesBeforeCheckpoint = accountant.previewFeesOwed();

            // Checkpoint via setLendingRate
            uint256 gasStart = gasleft();
            accountant.setLendingRate(2000); // Same rate, just to trigger checkpoint
            checkpointGas = gasStart - gasleft();

            // Verify checkpoint
            (, uint128 feesOwed,, uint96 storedRate,,,,,,) = accountant.accountantState();

            console.log("\n   Quarter %d Checkpoint:", i);
            console.log("     Rate increased from %d to %d", lastRate, storedRate);
            console.log("     Quarterly growth: %d bps", (storedRate - lastRate) * 10_000 / lastRate);
            console.log("     Fees checkpointed: %d", feesOwed);
            console.log("     Gas used: %d", checkpointGas);

            // Verify stored values match calculated
            assertEq(storedRate, rateBeforeCheckpoint, "Checkpointed rate mismatch");
            assertEq(feesOwed, feesBeforeCheckpoint, "Checkpointed fees mismatch");

            lastRate = storedRate;
        }

        // For continuous compounding at 20% APY, final rate should be ~1.22
        assertApproxEqRel(lastRate, 1.22e18, 0.02e18, "Final rate after 1 year"); // Adjusted expectation
    }

    function testInterestAccrualEdgeCases() external {
        console.log("\n=== TEST: Interest Accrual Edge Cases ===");

        // Test 1: Very short time periods (1 second)
        console.log("\n1. ULTRA SHORT PERIOD (1 second)");
        accountant.setMaxLendingRate(10_000); // Set max first
        accountant.setLendingRate(10_000); // 100% APY for easier calculation

        skip(1);
        (uint96 rateAfter1Sec,) = accountant.calculateExchangeRateWithInterest();

        // Expected rate increase for 1 second at 100% APY
        uint256 expectedIncrease = uint256(1e18).mulDivDown(10_000, 365 days * 10_000);
        console.log("   Rate after 1 second: %d", rateAfter1Sec);
        console.log("   Expected minimum increase: %d", expectedIncrease);

        assertGt(rateAfter1Sec, 1e18, "Rate should increase even for 1 second");

        // Test 2: Very long period (10 years)
        console.log("\n2. VERY LONG PERIOD (10 years)");
        skip(3650 days);

        (uint96 rateAfter10Years,) = accountant.calculateExchangeRateWithInterest();
        console.log("   Rate after 10 years at 100%% APY: %d", rateAfter10Years);

        assertGt(rateAfter10Years, 10e18, "Should have significant growth");

        // Test 3: Zero interest rate
        console.log("\n3. ZERO INTEREST RATE");
        accountant.setLendingRate(0);

        uint256 rateBeforeZero = accountant.getRate();
        skip(365 days);
        uint256 rateAfterZero = accountant.getRate();

        assertEq(rateAfterZero, rateBeforeZero, "Rate should not change with 0% interest");
        console.log("   Rate unchanged at: %d", rateAfterZero);
    }

    function testProtocolFeeAccrualMath() external {
        console.log("\n=== TEST: Protocol Fee Accrual Math ===");

        uint256 deposits = 1000e18;

        uint256[4] memory periods = [uint256(1 days), 30 days, 90 days, 365 days];
        string[4] memory labels = ["1 day", "30 days", "90 days", "365 days"];

        for (uint256 i = 0; i < periods.length; i++) {
            // Reset state completely
            vm.warp(0);
            accountant = new AccountantWithRateProviders(
                address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
            );
            rolesAuthority.setUserRole(address(accountant), UPDATE_EXCHANGE_RATE_ROLE, true);
            rolesAuthority.setUserRole(address(accountant), ADMIN_ROLE, true);
            accountant.setLendingRate(1000);
            accountant.setManagementFeeRate(200);

            skip(periods[i]);

            // Get current value INCLUDING interest
            (uint96 currentRate,) = accountant.calculateExchangeRateWithInterest();
            uint256 currentValue = deposits.mulDivDown(currentRate, 1e18);

            // Management fee is 2% ANNUAL, but we need to adjust for time period
            uint256 expectedFees = currentValue.mulDivDown(200, 10_000) // 2% annual rate
                .mulDivDown(periods[i], 365 days); // Adjust for actual time period

            uint256 actualFees = accountant.previewFeesOwed();

            console.log("\n   Period: %s", labels[i]);
            console.log("     Current value: %d", currentValue);
            console.log("     Expected fees: %d", expectedFees);
            console.log("     Actual fees: %d", actualFees);

            assertApproxEqRel(actualFees, expectedFees, 0.01e18, "Management fees should be 2% annualized");
        }
    }

    function testContinuousCompoundingVsSimple() external {
        console.log("\n=== TEST: Interest Calculation Method ===");

        // Compare calculation method using fresh accountants for each test
        uint256[3] memory periods = [uint256(30 days), 180 days, 365 days];

        for (uint256 i = 0; i < periods.length; i++) {
            // Create fresh accountant for each period test
            AccountantWithRateProviders testAccountant = new AccountantWithRateProviders(
                address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
            );
            rolesAuthority.setUserRole(address(testAccountant), UPDATE_EXCHANGE_RATE_ROLE, true);
            testAccountant.setLendingRate(1000); // 10%

            skip(periods[i]);

            (uint96 actualRate,) = testAccountant.calculateExchangeRateWithInterest();

            // Simple interest calculation
            uint256 simpleRate = 1e18 + (1e18 * 1000 * periods[i]) / (10_000 * 365 days);

            console.log("\n   Period: %d days", periods[i] / 1 days);
            console.log("     Actual rate: %d", actualRate);
            console.log("     Simple rate: %d", simpleRate);

            // The contract uses simple interest
            assertEq(actualRate, simpleRate, "Contract uses simple interest calculation");
        }
    }

    function testRateUpdateBounds() external {
        console.log("\n=== TEST: Rate Update Bounds with Interest ===");

        // Set tight bounds
        accountant.updateUpper(10_100); // 1% upper
        accountant.updateLower(9900); // 1% lower

        // Set lending rate
        accountant.setLendingRate(500); // 5% APY

        // Let interest accrue
        skip(73 days); // ~20% of year, so ~1% growth

        // Get current rate with interest
        (uint96 currentRate,) = accountant.calculateExchangeRateWithInterest();
        console.log("   Rate after 73 days at 5%% APY: %d", currentRate);

        // Try to update within bounds
        uint96 newRate = uint96(uint256(currentRate).mulDivDown(10_050, 10_000));
        accountant.updateExchangeRate(newRate);

        (,,,,,,, bool isPaused,,) = accountant.accountantState();
        assertFalse(isPaused, "Should not pause within bounds");

        // Try to update outside bounds
        skip(1 days);
        newRate = uint96(uint256(currentRate).mulDivDown(10_200, 10_000)); // 2% increase
        accountant.updateExchangeRate(newRate);

        (,,,,,,, isPaused,,) = accountant.accountantState();
        assertTrue(isPaused, "Should pause outside bounds");
    }

    function testStateConsistencyAcrossOperations() external {
        console.log("\n=== TEST: State Consistency Across Operations ===");

        // Setup
        accountant.setLendingRate(1500);
        accountant.setManagementFeeRate(300);

        // Track state at each step
        uint256 step = 1;

        // Step 1: Initial state
        console.log("\n   Step %d: Initial state", step++);
        _logState();

        // Step 2: After time passes
        skip(30 days);
        console.log("\n   Step %d: After 30 days (no checkpoint)", step++);
        _logState();

        // Step 3: After rate change (triggers checkpoint)
        accountant.setLendingRate(2000);
        console.log("\n   Step %d: After rate change (checkpoint)", step++);
        _logState();

        // Step 4: After manual update
        skip(15 days);
        (uint96 currentRate,) = accountant.calculateExchangeRateWithInterest();
        accountant.updateExchangeRate(currentRate);
        console.log("\n   Step %d: After manual update", step++);
        _logState();

        // Step 5: After fee claim
        (, uint128 feesOwed,,,,,,,,) = accountant.accountantState();
        if (feesOwed > 0) {
            deal(address(WETH), address(boringVault), feesOwed);
            vm.startPrank(address(boringVault));
            WETH.approve(address(accountant), feesOwed);
            accountant.claimFees(WETH);
            vm.stopPrank();
        }
        console.log("\n   Step %d: After fee claim", step++);
        _logState();
    }

    function _logState() internal view {
        (uint96 liveRate,) = accountant.calculateExchangeRateWithInterest();
        (, uint128 feesOwed,, uint96 storedRate,,, uint64 lastUpdate,,,) = accountant.accountantState();
        uint256 previewFees = accountant.previewFeesOwed();

        console.log("     Live rate: %d", liveRate);
        console.log("     Stored rate: %d", storedRate);
        console.log("     Stored fees: %d", feesOwed);
        console.log("     Preview fees: %d", previewFees);
        console.log("     Last update: %d", lastUpdate);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

interface MantleLspStaking {
    function mETHToETH(uint256) external view returns (uint256);
}

interface PriceRouter {
    function getValue(address, uint256, address) external view returns (uint256);
}
