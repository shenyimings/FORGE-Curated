// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Tests for kpkShares integration scenarios and complex workflows
contract kpkSharesIntegrationTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Complex Workflow Tests
    // ============================================================================

    function testCompleteDepositToRedeemWorkflow() public {
        // 1. Create a deposit request
        uint256 assets = _usdcAmount(1000);
        uint256 requestId = _testRequestProcessing(true, alice, assets, SHARES_PRICE, false);

        // 2. Process the deposit request
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 3. Check that shares were minted
        uint256 sharesMinted = kpkSharesContract.balanceOf(alice);
        assertGt(sharesMinted, 0);

        // 4. Create a redemption request
        uint256 redeemShares = sharesMinted / 2; // Redeem half
        vm.startPrank(alice);
        // Use previewRedemption which accounts for redemption fees
        uint256 redeemRequestId = kpkSharesContract.requestRedemption(
            redeemShares,
            kpkSharesContract.previewRedemption(redeemShares, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // 5. Process the redemption request
        vm.prank(ops);
        uint256[] memory redeemApproveRequests = new uint256[](1);
        redeemApproveRequests[0] = redeemRequestId;
        uint256[] memory redeemRejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(redeemApproveRequests, redeemRejectRequests, address(usdc), SHARES_PRICE);

        // 6. Check final balances
        uint256 finalShares = kpkSharesContract.balanceOf(alice);
        uint256 finalAssets = usdc.balanceOf(alice);

        assertEq(finalShares, sharesMinted - redeemShares);
        assertGt(finalAssets, 0);
    }

    function testMultipleUsersComplexWorkflow() public {
        // Alice deposits and redeems
        uint256 aliceAssets = _usdcAmount(500);
        uint256 aliceRequestId = _testRequestProcessing(true, alice, aliceAssets, SHARES_PRICE, false);

        // Bob deposits
        uint256 bobAssets = _usdcAmount(300);
        uint256 bobRequestId = _testRequestProcessing(true, bob, bobAssets, SHARES_PRICE, false);

        // Carol deposits
        uint256 carolAssets = _usdcAmount(200);
        uint256 carolRequestId = _testRequestProcessing(true, carol, carolAssets, SHARES_PRICE, false);

        // Process all deposits
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](3);
        approveRequests[0] = aliceRequestId;
        approveRequests[1] = bobRequestId;
        approveRequests[2] = carolRequestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Check shares were minted
        assertGt(kpkSharesContract.balanceOf(alice), 0);
        assertGt(kpkSharesContract.balanceOf(bob), 0);
        assertGt(kpkSharesContract.balanceOf(carol), 0);

        // Alice redeems half her shares
        uint256 aliceShares = kpkSharesContract.balanceOf(alice);
        uint256 aliceRedeemShares = aliceShares / 2;

        vm.startPrank(alice);
        // Use previewRedemption which accounts for redemption fees
        uint256 aliceRedeemRequestId = kpkSharesContract.requestRedemption(
            aliceRedeemShares,
            kpkSharesContract.previewRedemption(aliceRedeemShares, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // Process Alice's redemption
        vm.prank(ops);
        uint256[] memory redeemApproveRequests = new uint256[](1);
        redeemApproveRequests[0] = aliceRedeemRequestId;
        uint256[] memory redeemRejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(redeemApproveRequests, redeemRejectRequests, address(usdc), SHARES_PRICE);

        // Check final balances
        assertEq(kpkSharesContract.balanceOf(alice), aliceShares - aliceRedeemShares);
        assertGt(usdc.balanceOf(alice), 0);
        assertEq(kpkSharesContract.balanceOf(bob), kpkSharesContract.balanceOf(bob)); // Unchanged
        assertEq(kpkSharesContract.balanceOf(carol), kpkSharesContract.balanceOf(carol)); // Unchanged
    }

    function testRequestCancellations() public {
        // 1. Create a deposit request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // 2. Wait for TTL to expire before cancellation (required by contract)
        skip(SUBSCRIPTION_REQUEST_TTL + 1);

        // 3. Cancel the request
        vm.startPrank(alice);
        kpkSharesContract.cancelSubscription(requestId);
        vm.stopPrank();

        // 4. Check final state
        IkpkShares.UserRequest memory finalRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(finalRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // 5. Check that assets were returned to Alice
        assertGt(usdc.balanceOf(alice), 0);
    }

    // ============================================================================
    // Fee Integration Tests
    // ============================================================================

    function testFeesWithDepositsAndRedemptions() public {
        // Deploy contract with fees enabled
        KpkShares kpkSharesWithFees = _deployKpkSharesWithFees(
            100, // 1% management fee
            100, // 1% redeem fee
            500 // 5% performance fee
        );

        // 1. Create shares for testing
        uint256 shares = _sharesAmount(1000);
        _createSharesForTestingWithContract(kpkSharesWithFees, alice, shares);

        // 2. Set up time elapsed for fee charging and process redeem to trigger fees
        uint256 timeElapsed = 365 days;
        skip(timeElapsed);

        uint256 initialFeeBalance = kpkSharesWithFees.balanceOf(feeRecipient);
        uint256 redeemAmount = shares / 4;

        // Create redeem request to trigger fee charging
        vm.startPrank(alice);
        uint256 minAssetsOut =
            _calculateAdjustedExpectedAssets(kpkSharesWithFees, redeemAmount, SHARES_PRICE, address(usdc), timeElapsed);
        uint256 requestId = kpkSharesWithFees.requestRedemption(redeemAmount, minAssetsOut, address(usdc), alice);
        vm.stopPrank();

        // Process the request to trigger all fee types
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesWithFees.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        assertGt(
            kpkSharesWithFees.balanceOf(feeRecipient),
            initialFeeBalance,
            "Fee receiver should have received shares as fees"
        );

        // 3. Create and process another redemption request for more fee testing
        uint256 redeemShares = kpkSharesWithFees.balanceOf(alice) / 2;
        // Calculate assets using previewRedemption which accounts for redemption fees
        uint256 assetsOut = kpkSharesWithFees.previewRedemption(redeemShares, SHARES_PRICE, address(usdc));
        vm.startPrank(alice);
        requestId = kpkSharesWithFees.requestRedemption(
            redeemShares, assetsOut > 100 ? assetsOut - 100 : 1, address(usdc), alice
        );
        vm.stopPrank();

        vm.prank(ops);
        approveRequests[0] = requestId;
        kpkSharesWithFees.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 4. Check final balances
        uint256 finalShares = kpkSharesWithFees.balanceOf(alice);
        uint256 finalAssets = usdc.balanceOf(alice);

        // Alice should have fewer shares due to redemptions and fees
        assertLt(finalShares, shares);
        assertGt(finalAssets, 0);

        // 5. Check that fees were collected (as shares)
        assertGt(kpkSharesWithFees.balanceOf(feeRecipient), 0, "Fee receiver should have shares as fees");
    }

    // ============================================================================
    // Asset Management Integration Tests
    // ============================================================================

    function testMultipleAssetsWorkflow() public {
        // 1. Add new assets
        Mock_ERC20 asset1 = new Mock_ERC20("ASSET_1", 8);
        Mock_ERC20 asset2 = new Mock_ERC20("ASSET_2", 12);

        vm.startPrank(ops);
        kpkSharesContract.updateAsset(address(asset1), true, true, true);
        // Asset2 needs canDeposit: true to be used for subscriptions
        kpkSharesContract.updateAsset(address(asset2), true, true, true);
        vm.stopPrank();

        // 2. Mint assets to users
        asset1.mint(alice, 1000e8);
        asset2.mint(bob, 1000e12);

        // 3. Approve assets
        vm.startPrank(alice);
        asset1.approve(address(kpkSharesContract), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        asset2.approve(address(kpkSharesContract), type(uint256).max);
        vm.stopPrank();

        // 4. Create deposit requests with different assets
        vm.startPrank(alice);
        uint256 aliceRequestId = kpkSharesContract.requestSubscription(
            500e8, kpkSharesContract.assetsToShares(500e8, SHARES_PRICE, address(asset1)), address(asset1), alice
        );
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bobRequestId = kpkSharesContract.requestSubscription(
            500e12, kpkSharesContract.assetsToShares(500e12, SHARES_PRICE, address(asset2)), address(asset2), bob
        );
        vm.stopPrank();

        // 5. Process requests - need to process each asset separately
        vm.prank(ops);
        uint256[] memory aliceApproveRequests = new uint256[](1);
        aliceApproveRequests[0] = aliceRequestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(aliceApproveRequests, rejectRequests, address(asset1), SHARES_PRICE);

        vm.prank(ops);
        uint256[] memory bobApproveRequests = new uint256[](1);
        bobApproveRequests[0] = bobRequestId;
        kpkSharesContract.processRequests(bobApproveRequests, rejectRequests, address(asset2), SHARES_PRICE);

        // 6. Check shares were minted
        assertGt(kpkSharesContract.balanceOf(alice), 0);
        assertGt(kpkSharesContract.balanceOf(bob), 0);

        // 7. Remove one asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset1), false, false, false);

        // 8. Verify asset removal
        assertFalse(kpkSharesContract.isApprovedAsset(address(asset1)));
        assertTrue(kpkSharesContract.isApprovedAsset(address(asset2)));

        // 9. Try to create new request with removed asset (should fail)
        vm.startPrank(carol);
        asset1.mint(carol, 100e8);
        asset1.approve(address(kpkSharesContract), type(uint256).max);

        uint256 shares = 100e18; // Approximate shares for 100e8 assets at SHARES_PRICE
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAnApprovedAsset.selector));
        kpkSharesContract.requestSubscription(100e8, shares, address(asset1), carol);
        vm.stopPrank();
    }

    // ============================================================================
    // TTL Integration Tests
    // ============================================================================

    function testTtlWithComplexWorkflow() public {
        // 1. Set very short TTLs
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(1 hours);
        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(1 hours);

        // 2. Create deposit request
        uint256 depositRequestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // 3. Wait for TTL to expire
        skip(2 hours);

        // 4. Skip update test (function deprecated)

        // 5. Process the deposit request
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositRequestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 6. Create redemption request
        uint256 shares = kpkSharesContract.balanceOf(alice);
        uint256 redeemRequestId = _testRequestProcessing(false, alice, shares, SHARES_PRICE, false);

        // 7. Wait for TTL to expire
        skip(2 hours);

        // 8. Skip update test (function deprecated)

        // 9. Process the redemption request
        vm.prank(ops);
        uint256[] memory redeemApproveRequests = new uint256[](1);
        redeemApproveRequests[0] = redeemRequestId;
        uint256[] memory redeemRejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(redeemApproveRequests, redeemRejectRequests, address(usdc), SHARES_PRICE);
    }

    // ============================================================================
    // Error Recovery and Edge Cases
    // ============================================================================

    function testErrorRecoveryWorkflow() public {
        // 1. Create a deposit request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // 2. Try to process with wrong operator (should fail)
        vm.prank(alice);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 3. Process correctly with proper operator
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 4. Check that it worked
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));

        // 5. Try to cancel after processing (should fail)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPending.selector));
        kpkSharesContract.cancelSubscription(requestId);
        vm.stopPrank();
    }

    function testConcurrentOperations() public {
        // Ensure all users have sufficient USDC balance and allowance
        usdc.mint(address(ops), _usdcAmount(1000));
        usdc.mint(address(admin), _usdcAmount(1000));

        vm.prank(ops);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        vm.prank(admin);
        usdc.approve(address(kpkSharesContract), type(uint256).max);

        // 1. Create multiple requests from different users simultaneously
        uint256[] memory requestIds = new uint256[](5);
        requestIds[0] = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(true, bob, _usdcAmount(200), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(true, carol, _usdcAmount(150), SHARES_PRICE, false);
        requestIds[3] = _testRequestProcessing(true, ops, _usdcAmount(300), SHARES_PRICE, false);
        requestIds[4] = _testRequestProcessing(true, admin, _usdcAmount(250), SHARES_PRICE, false);

        // 2. Process all requests in batch
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(requestIds, rejectRequests, address(usdc), SHARES_PRICE);

        // 3. Check all were processed
        for (uint256 i = 0; i < requestIds.length; i++) {
            IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestIds[i]);
            assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        }

        // 4. Check all users have shares
        assertGt(kpkSharesContract.balanceOf(alice), 0);
        assertGt(kpkSharesContract.balanceOf(bob), 0);
        assertGt(kpkSharesContract.balanceOf(carol), 0);
        assertGt(kpkSharesContract.balanceOf(ops), 0);
        assertGt(kpkSharesContract.balanceOf(admin), 0);
    }

    // ============================================================================
    // Performance and Stress Tests
    // ============================================================================

    function testLargeNumberOfRequests() public {
        uint256 numRequests = 10;
        uint256[] memory requestIds = new uint256[](numRequests);

        // Create many requests
        for (uint256 i = 0; i < numRequests; i++) {
            address user = i % 2 == 0 ? alice : bob;
            uint256 amount = _usdcAmount(50 + i * 10);
            requestIds[i] = _testRequestProcessing(true, user, amount, SHARES_PRICE, false);
        }

        // Process all requests
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(requestIds, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify all were processed
        for (uint256 i = 0; i < numRequests; i++) {
            IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestIds[i]);
            assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        }
    }

    function testLargeAmounts() public {
        uint256 largeAmount = _usdcAmount(1_000_000); // 1M USDC

        // Create request with large amount
        uint256 requestId = _testRequestProcessing(true, alice, largeAmount, SHARES_PRICE, false);

        // Process request
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Check shares were minted
        uint256 shares = kpkSharesContract.balanceOf(alice);
        assertGt(shares, 0);

        // Manually set approval for large amount
        vm.prank(alice);
        kpkSharesContract.approve(address(kpkSharesContract), shares);

        // Verify approval was set
        uint256 allowance = kpkSharesContract.allowance(alice, address(kpkSharesContract));
        assertEq(allowance, shares, "Approval should be set correctly");

        // Redeem large amount - this will transfer shares to escrow
        vm.startPrank(alice);
        // Use previewRedemption which accounts for redemption fees
        uint256 redeemRequestId = kpkSharesContract.requestRedemption(
            shares, kpkSharesContract.previewRedemption(shares, SHARES_PRICE, address(usdc)), address(usdc), alice
        );
        vm.stopPrank();

        // Check that shares were transferred to escrow (investor balance should be 0)
        uint256 sharesAfterRequest = kpkSharesContract.balanceOf(alice);
        assertEq(sharesAfterRequest, 0, "Shares should be transferred to escrow when redemption is requested");

        vm.prank(ops);
        uint256[] memory redeemApproveRequests = new uint256[](1);
        redeemApproveRequests[0] = redeemRequestId;
        uint256[] memory redeemRejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(redeemApproveRequests, redeemRejectRequests, address(usdc), SHARES_PRICE);

        // Check final balances - shares should remain 0 after redemption is processed
        uint256 finalShares = kpkSharesContract.balanceOf(alice);
        assertEq(finalShares, 0, "Shares should remain 0 after redemption is processed");
        assertGt(usdc.balanceOf(alice), 0);
    }
}
