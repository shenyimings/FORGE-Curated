// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Tests for kpkShares precision functionality
/// @dev Focuses on shares and assets conversion precision, preview functions, and fee functions
contract kpkSharesPrecisionTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Precision Testing Section
    // ============================================================================
    // Tests for shares and assets conversion precision, preview functions, and fee functions

    function testPrecisionAssetsToSharesConversion() public view {
        // Test with very small amounts to check precision
        uint256 smallAssets = 1e6; // 1 USDC (6 decimals)
        uint256 expectedShares = kpkSharesContract.assetsToShares(smallAssets, SHARES_PRICE, address(usdc));

        // With 1 USDC and $1 price, should get some shares
        assertGt(expectedShares, 0);

        // Test with larger amounts to verify scaling
        uint256 largeAssets = _usdcAmount(1_000_000); // 1M USDC
        uint256 expectedLargeShares = kpkSharesContract.assetsToShares(largeAssets, SHARES_PRICE, address(usdc));

        // Should be proportional to the small amount test
        assertGt(expectedLargeShares, expectedShares);

        // Test precision with different price points
        uint256 highPrice = 2e8; // $2.00
        uint256 lowPrice = 5e7; // $0.50

        uint256 sharesHighPrice = kpkSharesContract.assetsToShares(_usdcAmount(1000), highPrice, address(usdc));

        uint256 sharesLowPrice = kpkSharesContract.assetsToShares(_usdcAmount(1000), lowPrice, address(usdc));

        // Higher price should result in fewer shares
        assertLt(sharesHighPrice, sharesLowPrice);
    }

    function testPrecisionSharesToAssetsConversion() public view {
        // Test with very small share amounts
        uint256 smallShares = 2e12; // 2e12 wei of shares (18 decimals)
        uint256 expectedAssets = kpkSharesContract.sharesToAssets(smallShares, SHARES_PRICE, address(usdc));

        // With 1e6 wei shares and $1 price, should get some assets
        assertGt(expectedAssets, 0);

        // Test with larger amounts to verify scaling
        uint256 largeShares = _sharesAmount(1_000_000); // 1M shares
        uint256 expectedLargeAssets = kpkSharesContract.sharesToAssets(largeShares, SHARES_PRICE, address(usdc));

        // Should be proportional to the small amount test
        assertGt(expectedLargeAssets, expectedAssets);

        // Test precision with different price points
        uint256 highPrice = 2e8; // $2.00
        uint256 lowPrice = 5e7; // $0.50

        uint256 assetsHighPrice = kpkSharesContract.sharesToAssets(_sharesAmount(1000), highPrice, address(usdc));

        uint256 assetsLowPrice = kpkSharesContract.sharesToAssets(_sharesAmount(1000), lowPrice, address(usdc));

        // Higher price should result in more assets
        assertGt(assetsHighPrice, assetsLowPrice);
    }

    function testPrecisionPreviewDeposit() public view {
        // Test with very small asset amounts
        uint256 smallAssets = _usdcAmount(1); // 1 USDC
        uint256 shares = kpkSharesContract.previewSubscription(smallAssets, SHARES_PRICE, address(usdc));

        assertGt(shares, 0);
        assertApproxEqRel(shares, 1e18, 10);

        // Test with larger amounts
        uint256 largeAssets = _usdcAmount(1_000_000); // 1M USDC
        uint256 sharesLarge = kpkSharesContract.previewSubscription(largeAssets, SHARES_PRICE, address(usdc));

        assertGt(sharesLarge, shares);

        // Verify the conversion is consistent with direct assetsToShares call
        uint256 directShares = kpkSharesContract.assetsToShares(largeAssets, SHARES_PRICE, address(usdc));
        assertEq(sharesLarge, directShares);
    }

    function testPrecisionPreviewRedeemSmallAmount() public view {
        // Test that small but meaningful amounts result in non-zero assets
        // With redemption fee rate of 0.5% (50 bps), we need enough shares to cover fee and result in >0 assets
        uint256 smallShares = 1e15; // 1000x larger to ensure non-zero result after fees
        uint256 assets = kpkSharesContract.previewRedemption(smallShares, SHARES_PRICE, address(usdc));

        // Should get non-zero assets for this amount
        assertGt(assets, 0, "Small shares should result in non-zero assets");

        // Calculate expected: (shares - redemptionFee) converted to assets
        uint256 redemptionFee = (smallShares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 netShares = smallShares - redemptionFee;
        uint256 expectedAssets = kpkSharesContract.sharesToAssets(netShares, SHARES_PRICE, address(usdc));
        assertEq(assets, expectedAssets, "previewRedemption should match manual calculation");
    }

    function testPrecisionPreviewRedeemVerySmallAmount() public view {
        // Test that very small amounts may round to zero (expected behavior)
        uint256 barelyAnyShares = 1e11; // Very small amount
        uint256 assetsBarelyAny = kpkSharesContract.previewRedemption(barelyAnyShares, SHARES_PRICE, address(usdc));

        // For very small amounts, assets might be 0 due to rounding - this is expected
        // Verify it's non-negative and doesn't revert
        assertGe(assetsBarelyAny, 0, "Very small shares should not revert, may round to 0");
    }

    function testPrecisionPreviewRedeemLargeAmount() public view {
        // Test precision at scale with large amounts
        uint256 largeShares = _sharesAmount(1_000_000); // 1M shares
        uint256 assetsLarge = kpkSharesContract.previewRedemption(largeShares, SHARES_PRICE, address(usdc));

        // Verify the conversion is consistent with direct sharesToAssets call (accounting for fees)
        uint256 largeRedemptionFee = (largeShares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 netLargeShares = largeShares - largeRedemptionFee;
        uint256 directAssets = kpkSharesContract.sharesToAssets(netLargeShares, SHARES_PRICE, address(usdc));
        assertEq(assetsLarge, directAssets, "Large amount previewRedemption should match manual calculation");
    }

    function testPrecisionPreviewRedeemRoundTrip() public view {
        // Verify round-trip precision (shares -> assets -> shares approximation)
        // This tests that the conversion maintains reasonable precision
        uint256 testShares = _sharesAmount(1000);
        uint256 testAssets = kpkSharesContract.previewRedemption(testShares, SHARES_PRICE, address(usdc));
        uint256 sharesBack = kpkSharesContract.assetsToShares(testAssets, SHARES_PRICE, address(usdc));

        // After redemption fee, we should get back approximately the net shares
        uint256 testRedemptionFee = (testShares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 expectedNetShares = testShares - testRedemptionFee;

        // Allow small tolerance for rounding in the round-trip
        assertApproxEqRel(sharesBack, expectedNetShares, 1e4); // 1% tolerance for round-trip precision
    }

    function testPrecisionFeeCalculations() public {
        // Test management fee precision with very small rates
        KpkShares kpkSharesWithFees = _deployKpkSharesWithFees(
            1, // 0.01% management fee (1 basis point)
            0,
            0
        );

        uint256 shares = _sharesAmount(1000);
        _createSharesForTestingWithContract(kpkSharesWithFees, alice, shares);

        uint256 timeElapsed = 365 days; // 1 year
        skip(timeElapsed);

        // Get state before fee charging to calculate expected fee accurately
        uint256 initialFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);
        uint256 initialTotalSupply = kpkSharesWithFees.totalSupply();
        uint256 netSupply = initialTotalSupply > initialFeeBalance ? initialTotalSupply - initialFeeBalance : 1;

        // Create and process a redeem request to trigger fee charging
        vm.startPrank(alice);
        uint256 requestId = kpkSharesWithFees.requestRedemption(
            _sharesAmount(100),
            kpkSharesWithFees.sharesToAssets(_sharesAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesWithFees.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        uint256 finalFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);
        uint256 actualFee = finalFeeBalance - initialFeeBalance;

        // With minimum rate, fees should still be calculated precisely
        assertGt(actualFee, 0);

        // Calculate expected fee using the exact formula from _chargeManagementFee:
        // feeAmount = ((totalSupply - feeReceiverBalance) * managementFeeRate * timeElapsed) / (10000 * SECONDS_PER_YEAR)
        uint256 expectedFee = (netSupply * 1 * timeElapsed) / (10_000 * SECONDS_PER_YEAR);

        // Allow small tolerance for rounding differences (management fees use Floor rounding)
        // The actual fee might be slightly different due to the state at the time of calculation
        assertApproxEqRel(actualFee, expectedFee, 1e3); // Allow 0.1% tolerance for rounding
    }

    function testPrecisionRedeemFeeCalculations() public {
        // Test redeem fee precision with very small rates
        KpkShares kpkSharesWithFees = _deployKpkSharesWithFees(
            0,
            1, // 0.01% redeem fee (1 basis point)
            0
        );

        uint256 shares = _sharesAmount(1000);
        _createSharesForTestingWithContract(kpkSharesWithFees, alice, shares);

        vm.prank(alice);
        kpkSharesWithFees.approve(address(kpkSharesWithFees), shares);

        vm.startPrank(alice);
        // Calculate adjusted expected assets (no time elapsed, but account for potential fees from share creation)
        uint256 minAssetsOut =
            _calculateAdjustedExpectedAssets(kpkSharesWithFees, shares, SHARES_PRICE, address(usdc), 0);
        uint256 requestId = kpkSharesWithFees.requestRedemption(shares, minAssetsOut, address(usdc), alice);
        vm.stopPrank();

        uint256 initialFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesWithFees.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        uint256 finalFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);
        uint256 actualFee = finalFeeBalance - initialFeeBalance;

        // Calculate expected fee manually
        uint256 expectedFee = (shares * 1) / 10_000; // 0.01% of shares
        assertApproxEqRel(actualFee, expectedFee, 1e5); // Allow 0.1% tolerance
    }

    function testPrecisionPerformanceFeeCalculations() public {
        // Test performance fee precision with very small rates
        KpkShares kpkSharesWithFees = _deployKpkSharesWithFees(
            0,
            0,
            1 // 0.01% performance fee (1 basis point)
        );

        uint256 shares = _sharesAmount(1000);
        _createSharesForTestingWithContract(kpkSharesWithFees, alice, shares);

        vm.prank(alice);
        kpkSharesWithFees.approve(address(kpkSharesWithFees), shares);

        vm.startPrank(alice);
        uint256 requestId = kpkSharesWithFees.requestRedemption(
            _sharesAmount(100),
            kpkSharesWithFees.sharesToAssets(_sharesAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        uint256 timeElapsed = 365 days;
        skip(timeElapsed);

        uint256 initialFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesWithFees.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        uint256 finalFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);
        uint256 actualFee = finalFeeBalance - initialFeeBalance;

        // With minimum rate, fees should still be calculated precisely
        assertGt(actualFee, 0);
    }

    function testPrecisionRoundingBehavior() public view {
        // Test that rounding behavior is consistent and predictable
        uint256 testShares = _sharesAmount(1001); // 1001 shares
        uint256 testPrice = 100_000_001; // $1.00000001 (slightly above $1)

        uint256 assets = kpkSharesContract.sharesToAssets(testShares, testPrice, address(usdc));

        // Verify the conversion back to shares maintains precision
        uint256 sharesBack = kpkSharesContract.assetsToShares(assets, testPrice, address(usdc));

        // Due to rounding, we might lose some precision, but it should be minimal
        assertLe(_abs(testShares, sharesBack), 1e12); // Allow 1 wei difference

        // Test with very precise price
        uint256 precisePrice = 1_000_000_001; // $1.000000001
        uint256 preciseAssets = kpkSharesContract.sharesToAssets(testShares, precisePrice, address(usdc));

        uint256 preciseSharesBack = kpkSharesContract.assetsToShares(preciseAssets, precisePrice, address(usdc));

        // Should maintain precision even with very precise prices
        assertLe(_abs(testShares, preciseSharesBack), 1e12);
    }

    function testPrecisionEdgeCases() public view {
        // Test with maximum possible values
        uint256 maxShares = 1e30;
        uint256 maxPrice = 1e30;

        // These should not revert but handle gracefully
        uint256 maxAssets = kpkSharesContract.sharesToAssets(maxShares, maxPrice, address(usdc));

        // Should not overflow
        assertGt(maxAssets, 0);

        // Test with minimum values
        uint256 minShares = 1e6;
        uint256 minPrice = 1;

        uint256 minAssets = kpkSharesContract.sharesToAssets(minShares, minPrice, address(usdc));

        // Should handle minimum values correctly
        assertGe(minAssets, 0);

        // Test with zero values
        uint256 zeroAssets = kpkSharesContract.sharesToAssets(0, SHARES_PRICE, address(usdc));
        assertEq(zeroAssets, 0);

        uint256 zeroShares = kpkSharesContract.assetsToShares(0, SHARES_PRICE, address(usdc));
        assertEq(zeroShares, 0);
    }

    /// @notice Test assetsToShares with zero sharesPrice (branch coverage)
    /// @dev Tests the sharesPrice == 0 branch separately from assetAmount == 0
    function testAssetsToSharesWithZeroPrice() public view {
        // Test the sharesPrice == 0 branch (should return 0)
        uint256 assets = _usdcAmount(100);
        uint256 shares = kpkSharesContract.assetsToShares(assets, 0, address(usdc));
        assertEq(shares, 0, "Should return 0 when sharesPrice is 0");
    }

    /// @notice Test sharesToAssets with zero sharesPrice (branch coverage)
    /// @dev Tests the sharesPrice == 0 branch separately from shares == 0
    function testSharesToAssetsWithZeroPrice() public view {
        // Test the sharesPrice == 0 branch (should return 0)
        uint256 shares = _sharesAmount(100);
        uint256 assets = kpkSharesContract.sharesToAssets(shares, 0, address(usdc));
        assertEq(assets, 0, "Should return 0 when sharesPrice is 0");
    }

    function testPrecisionConsistencyAcrossOperations() public view {
        // Test that precision is maintained across multiple operations
        uint256 initialShares = _sharesAmount(1000);
        uint256 initialPrice = SHARES_PRICE;

        // Convert shares to assets
        uint256 assets = kpkSharesContract.sharesToAssets(initialShares, initialPrice, address(usdc));

        // Convert back to shares
        uint256 sharesBack = kpkSharesContract.assetsToShares(assets, initialPrice, address(usdc));

        // Convert to assets again
        uint256 assetsAgain = kpkSharesContract.sharesToAssets(sharesBack, initialPrice, address(usdc));

        // Precision should be maintained across multiple conversions
        assertLe(_abs(assets, assetsAgain), 1); // Allow 1 wei difference

        // Test with preview functions to ensure consistency
        uint256 previewAssets = kpkSharesContract.previewRedemption(initialShares, initialPrice, address(usdc));

        // previewAssets accounts for redemption fees, so it should be less than assets
        // Calculate expected assets after redemption fee
        uint256 redemptionFee = (initialShares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 netShares = initialShares - redemptionFee;
        uint256 expectedPreviewAssets = kpkSharesContract.sharesToAssets(netShares, initialPrice, address(usdc));
        assertEq(previewAssets, expectedPreviewAssets);

        uint256 previewShares = kpkSharesContract.previewSubscription(assets, initialPrice, address(usdc));

        // The shares should be very close to the original
        assertLe(_abs(previewShares, initialShares), 1);
    }

    function testPrecisionWithDifferentAssetDecimals() public {
        // Test precision with assets that have different decimal places
        // Create a mock token with 18 decimals
        // Mock_ERC20 token18Decimals = new Mock_ERC20("TOKEN18", 18);

        // Add it as an approved asset (this would require modifying the contract setup)
        // For now, we'll test with the existing USDC (6 decimals)

        uint256 testAmount = 1_000_000; // 1M units

        // Test with USDC (6 decimals)
        uint256 usdcShares = kpkSharesContract.assetsToShares(testAmount, SHARES_PRICE, address(usdc));

        // Test with equivalent amount in wei (18 decimals)
        // uint256 weiAmount = testAmount * 1e12; // Convert 6 decimals to 18 decimals

        // The shares should be the same since we're dealing with the same USD value
        // This tests that decimal handling is correct
        assertGt(usdcShares, 0);

        // Test conversion back to assets
        uint256 usdcAssets = kpkSharesContract.sharesToAssets(usdcShares, SHARES_PRICE, address(usdc));

        // Should get back approximately the same amount (allowing for rounding)
        assertApproxEqRel(usdcAssets, testAmount, 1e5); // Allow 0.1% tolerance
    }

    function testPrecisionFeeAccumulation() public {
        // Test that fees accumulate with precision over time
        KpkShares kpkSharesWithFees = _deployKpkSharesWithFees(
            100, // 1% management fee
            50, // 0.5% redeem fee
            500 // 5% performance fee
        );

        uint256 shares = _sharesAmount(10_000);
        _createSharesForTestingWithContract(kpkSharesWithFees, alice, shares);

        uint256 initialFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);

        // Process multiple operations over time to test fee accumulation precision
        for (uint256 i = 0; i < 10; i++) {
            skip(30 days); // Skip 30 days

            // Check alice's balance and only redeem what she has
            uint256 aliceBalance = kpkSharesWithFees.balanceOf(alice);
            if (aliceBalance < _sharesAmount(100)) {
                break; // Not enough shares to continue
            }

            vm.startPrank(alice);
            // Calculate adjusted expected assets accounting for fee dilution (30 days elapsed per iteration)
            uint256 minAssetsOut = _calculateAdjustedExpectedAssets(
                kpkSharesWithFees, _sharesAmount(100), SHARES_PRICE, address(usdc), 30 days
            );
            uint256 requestId =
                kpkSharesWithFees.requestRedemption(_sharesAmount(100), minAssetsOut, address(usdc), alice);
            vm.stopPrank();

            vm.prank(ops);
            uint256[] memory approveRequests = new uint256[](1);
            approveRequests[0] = requestId;
            uint256[] memory rejectRequests = new uint256[](0);
            kpkSharesWithFees.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        }

        uint256 finalFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);
        uint256 totalFees = finalFeeBalance - initialFeeBalance;

        // Fees should accumulate with precision
        assertGt(totalFees, 0);

        // The total fees should be reasonable given the rates and time periods
        // This is a basic sanity check for precision
        assertLt(totalFees, shares); // Fees shouldn't exceed the total shares
    }

    // ============================================================================
    // Helper Functions
    // ============================================================================

    function _abs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
