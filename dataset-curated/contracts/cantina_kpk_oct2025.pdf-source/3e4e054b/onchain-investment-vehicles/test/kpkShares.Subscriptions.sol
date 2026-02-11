// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Tests for kpkShares subscription functionality
contract kpkSharesSubscriptionsTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Basic Subscription Request Tests
    // ============================================================================

    function testRequestSubscription() public {
        uint256 assets = _usdcAmount(100);
        uint256 sharesout = _sharesAmount(100);

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesout, address(usdc), alice);
        vm.stopPrank();

        assertEq(requestId, 1);

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestType), uint8(IkpkShares.RequestType.SUBSCRIPTION));
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING));
        assertEq(request.asset, address(usdc));
        assertEq(request.assetAmount, assets);

        assertEq(request.sharesAmount, sharesout);
        assertEq(request.receiver, alice);
        assertEq(request.investor, alice);
        assertEq(request.timestamp, block.timestamp);
    }

    function testRequestSubscriptionWithDifferentInvestor() public {
        uint256 assets = _usdcAmount(100);
        uint256 price = SHARES_PRICE;

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(
            assets,
            price,
            address(usdc),
            bob // receiver
        );
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.investor, alice); // Alice is the one making the request (msg.sender)
        assertEq(request.receiver, bob); // Bob is the receiver where shares will be sent
    }

    function testRequestSubscriptionWithUnapprovedAsset() public {
        // Create a new token that's not approved
        Mock_ERC20 unapprovedToken = new Mock_ERC20("UNAPPROVED", 18);
        unapprovedToken.mint(alice, 1000e18);

        vm.startPrank(alice);
        unapprovedToken.approve(address(kpkSharesContract), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAnApprovedAsset.selector));
        kpkSharesContract.requestSubscription(_usdcAmount(100), 100e18, address(unapprovedToken), alice);
        vm.stopPrank();
    }

    function testRequestSubscriptionWithZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.requestSubscription(0, 0, address(usdc), alice);
        vm.stopPrank();
    }

    function testRequestSubscriptionWithZeroPrice() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.requestSubscription(_usdcAmount(100), 0, address(usdc), alice);
        vm.stopPrank();
    }

    function testRequestSubscriptionWithZeroAddressReceiver() public {
        uint256 shares = kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc));
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.requestSubscription(_usdcAmount(100), shares, address(usdc), address(0));
        vm.stopPrank();
    }

    // ============================================================================
    // Subscription Preview Tests
    // ============================================================================

    function testPreviewSubscription() public {
        uint256 assets = _usdcAmount(100);
        uint256 price = SHARES_PRICE;

        vm.prank(alice);
        uint256 shares = kpkSharesContract.previewSubscription(assets, price, address(usdc));

        // Verify that shares are calculated correctly (should be > 0 for valid assets)
        assertGt(shares, 0);

        // Shares should be calculated using the contract's assetsToShares function
        uint256 expectedShares = kpkSharesContract.assetsToShares(assets, price, address(usdc));
        assertEq(shares, expectedShares);
    }

    function testPreviewSubscriptionWithUnapprovedAsset() public {
        Mock_ERC20 unapprovedToken = new Mock_ERC20("UNAPPROVED", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAnApprovedAsset.selector));
        kpkSharesContract.previewSubscription(_usdcAmount(100), SHARES_PRICE, address(unapprovedToken));
    }

    function testPreviewSubscriptionWithDifferentPrices() public view {
        uint256 assets = _usdcAmount(100);

        // Test with different prices
        uint256[] memory prices = new uint256[](3);
        prices[0] = SHARES_PRICE; // 1:1
        prices[1] = 2e8; // 2:1
        prices[2] = 5e7; // 0.5:1

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 shares = kpkSharesContract.previewSubscription(assets, prices[i], address(usdc));
            uint256 expectedShares = kpkSharesContract.assetsToShares(assets, prices[i], address(usdc));
            assertEq(shares, expectedShares);
        }
    }

    function testPreviewSubscriptionWithZeroPrice() public {
        // First, process a request to set last settled price
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now call previewSubscription with sharesPrice = 0
        // Should use last settled price
        uint256 assets = _usdcAmount(100);
        vm.prank(alice);
        uint256 shares = kpkSharesContract.previewSubscription(assets, 0, address(usdc));

        // Should calculate using last settled price (SHARES_PRICE)
        uint256 expectedShares = kpkSharesContract.assetsToShares(assets, SHARES_PRICE, address(usdc));
        assertEq(shares, expectedShares);
    }

    function testPreviewSubscriptionNoStoredPrice() public {
        // Call previewSubscription with sharesPrice = 0
        // Before any processing (no stored price exists)
        uint256 assets = _usdcAmount(100);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NoStoredPrice.selector));
        kpkSharesContract.previewSubscription(assets, 0, address(usdc));
    }

    /// @notice Test previewSubscription with both zero and non-zero price in same test
    /// @dev This explicitly tests both branches of the sharesPrice == 0 condition (line 205)
    function testPreviewSubscriptionBothBranches() public {
        uint256 assets = _usdcAmount(100);

        // First, test with non-zero price (sharesPrice != 0 branch)
        uint256 nonZeroPrice = SHARES_PRICE;
        uint256 shares1 = kpkSharesContract.previewSubscription(assets, nonZeroPrice, address(usdc));
        uint256 expectedShares1 = kpkSharesContract.assetsToShares(assets, nonZeroPrice, address(usdc));
        assertEq(shares1, expectedShares1, "Non-zero price branch should work correctly");

        // Process a request to set last settled price
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now test with zero price (sharesPrice == 0 branch, uses last settled price)
        uint256 shares2 = kpkSharesContract.previewSubscription(assets, 0, address(usdc));
        uint256 expectedShares2 = kpkSharesContract.assetsToShares(assets, SHARES_PRICE, address(usdc));
        assertEq(shares2, expectedShares2, "Zero price branch should use last settled price");

        // Both should give same result since we used same price
        assertEq(shares1, shares2, "Both branches should give same result with same underlying price");
    }

    // ============================================================================
    // View Function Tests
    // ============================================================================

    function testGetLastSettledPrice() public {
        // Initially, no price should be set (returns 0)
        uint256 initialPrice = kpkSharesContract.getLastSettledPrice(address(usdc));
        assertEq(initialPrice, 0, "Initial price should be 0");

        // Process a subscription request to set the last settled price
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify the last settled price is now set
        uint256 settledPrice = kpkSharesContract.getLastSettledPrice(address(usdc));
        assertEq(settledPrice, SHARES_PRICE, "Last settled price should match the processed price");

        // Process another request with a different price
        uint256 newPrice = SHARES_PRICE * 11 / 10; // 10% increase
        uint256 requestId2 = _testRequestProcessing(true, bob, _usdcAmount(100), newPrice, false);
        vm.prank(ops);
        uint256[] memory approveRequests2 = new uint256[](1);
        approveRequests2[0] = requestId2;
        kpkSharesContract.processRequests(approveRequests2, new uint256[](0), address(usdc), newPrice);

        // Verify the last settled price is updated
        uint256 updatedPrice = kpkSharesContract.getLastSettledPrice(address(usdc));
        assertEq(updatedPrice, newPrice, "Last settled price should be updated to new price");
    }

    function testGetLastSettledPriceForDifferentAssets() public {
        // First, set a price for USDC
        uint256 requestId1 = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests1 = new uint256[](1);
        approveRequests1[0] = requestId1;
        kpkSharesContract.processRequests(approveRequests1, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify USDC price is set
        uint256 usdcPriceBefore = kpkSharesContract.getLastSettledPrice(address(usdc));
        assertEq(usdcPriceBefore, SHARES_PRICE, "USDC price should be set");

        // Add a new asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        newAsset.mint(address(safe), _sharesAmount(100_000));
        newAsset.mint(address(alice), _sharesAmount(10_000));

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        vm.prank(safe);
        newAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Initially, no price should be set for the new asset
        uint256 initialPrice = kpkSharesContract.getLastSettledPrice(address(newAsset));
        assertEq(initialPrice, 0, "Initial price for new asset should be 0");

        // Process a subscription request for the new asset
        newAsset.mint(alice, _usdcAmount(100));
        vm.startPrank(alice);
        newAsset.approve(address(kpkSharesContract), _usdcAmount(100));
        uint256 requestId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(newAsset)),
            address(newAsset),
            alice
        );
        vm.stopPrank();

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(newAsset), SHARES_PRICE);

        // Verify the last settled price is set for the new asset
        uint256 settledPrice = kpkSharesContract.getLastSettledPrice(address(newAsset));
        assertEq(settledPrice, SHARES_PRICE, "Last settled price for new asset should be set");

        // Verify USDC price is still set (unchanged)
        uint256 usdcPriceAfter = kpkSharesContract.getLastSettledPrice(address(usdc));
        assertEq(usdcPriceAfter, SHARES_PRICE, "USDC price should still be set");
    }

    // ============================================================================
    // Subscription Processing Tests
    // ============================================================================

    function testProcessSubscriptionRequests() public {
        // Create multiple subscription requests
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(true, bob, _usdcAmount(200), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(true, carol, _usdcAmount(150), SHARES_PRICE, false);

        // Process all requests
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(requestIds, rejectRequests, address(usdc), SHARES_PRICE);

        // Check that all requests were processed
        for (uint256 i = 0; i < requestIds.length; i++) {
            IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestIds[i]);
            assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        }

        // Check that shares were minted
        assertGt(kpkSharesContract.balanceOf(alice), 0);
        assertGt(kpkSharesContract.balanceOf(bob), 0);
        assertGt(kpkSharesContract.balanceOf(carol), 0);
    }

    function testProcessSubscriptionRequestsWithRejections() public {
        // Create multiple subscription requests
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(true, bob, _usdcAmount(200), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(true, carol, _usdcAmount(150), SHARES_PRICE, false);

        // Process with some rejections
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](2);
        approveRequests[0] = requestIds[0];
        approveRequests[1] = requestIds[1];

        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestIds[2];

        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Check approved requests
        IkpkShares.UserRequest memory approvedRequest1 = kpkSharesContract.getRequest(requestIds[0]);
        assertEq(uint8(approvedRequest1.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));

        IkpkShares.UserRequest memory approvedRequest2 = kpkSharesContract.getRequest(requestIds[1]);
        assertEq(uint8(approvedRequest2.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));

        // Check rejected request
        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(requestIds[2]);
        assertEq(uint8(rejectedRequest.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));
    }

    function testProcessSubscriptionRequestsUnauthorized() public {
        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Try to process without operator role
        vm.prank(alice);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
    }

    function testProcessSubscriptionRequestsWithEmptyArrays() public {
        // Test processing with empty arrays
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](0);

        // Should not revert
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
    }

    // ============================================================================
    // Request Processing Edge Cases
    // ============================================================================

    function testProcessSubscriptionRequestWithMismatchedAsset() public {
        // Create subscription request for USDC
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Create a different asset
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));
        otherAsset.mint(address(alice), _sharesAmount(10_000));

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(otherAsset), true, true, true);

        // Grant allowance for the new asset
        vm.prank(safe);
        otherAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Try to process USDC request with different asset parameter
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        // Should skip the request (continue in loop) without processing
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(otherAsset), SHARES_PRICE);

        // Verify request is still pending (was skipped)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING));
    }

    function testProcessAlreadyProcessedSubscriptionRequest() public {
        // Create and process a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, true);

        // Try to process it again
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        // Should skip (continue in loop) without reverting
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify request is still processed (status unchanged)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
    }

    function testProcessAlreadyRejectedSubscriptionRequest() public {
        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Reject the request
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify request was rejected
        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(rejectedRequest.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));

        // Try to process it again (in approveRequests)
        vm.prank(ops);
        uint256[] memory approveRequests2 = new uint256[](1);
        approveRequests2[0] = requestId;
        // Should skip (continue in loop) without reverting
        kpkSharesContract.processRequests(approveRequests2, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify request is still rejected (status unchanged)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));
    }

    function testProcessAlreadyCancelledSubscriptionRequest() public {
        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Cancel the request
        skip(SUBSCRIPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Verify request was cancelled
        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(cancelledRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // Try to process it (in approveRequests)
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        // Should skip (continue in loop) without reverting
        // This tests the _checkValidRequest false path for non-pending status
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify request is still cancelled (status unchanged)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testCheckValidRequestWithNonPendingStatus() public {
        // Create and process a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, true);

        // Verify request is processed (not pending)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));

        // Try to process it again - should be skipped due to non-pending status
        // This explicitly tests the _checkValidRequest false path for non-pending status
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        // Should skip (continue in loop) without error
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify request is still processed (status unchanged)
        IkpkShares.UserRequest memory requestAfter = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(requestAfter.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
    }

    function testProcessRejectedSubscriptionSkipsMismatchedAsset() public {
        // Create subscription request for USDC
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Create a different asset
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));
        otherAsset.mint(address(alice), _sharesAmount(10_000));

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(otherAsset), true, true, true);

        // Grant allowance for the new asset
        vm.prank(safe);
        otherAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Try to reject USDC request with different asset parameter
        // Should skip the request (continue in loop) without processing
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(otherAsset), SHARES_PRICE);

        // Verify request is still pending (was skipped)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING));
    }

    function testProcessRejectedSubscriptionSkipsAlreadyProcessed() public {
        // Create and process a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, true);

        // Try to reject it (in rejectRequests) - should skip (continue in loop) without error
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify request is still processed (status unchanged)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
    }

    function testProcessRejectedSubscriptionSkipsAlreadyRejected() public {
        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Reject the request
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify request was rejected
        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(rejectedRequest.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));

        // Try to reject it again (in rejectRequests) - should skip (continue in loop) without reverting
        vm.prank(ops);
        uint256[] memory rejectRequests2 = new uint256[](1);
        rejectRequests2[0] = requestId;
        kpkSharesContract.processRequests(new uint256[](0), rejectRequests2, address(usdc), SHARES_PRICE);

        // Verify request is still rejected (status unchanged)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));
    }

    function testProcessRejectedSubscriptionSkipsAlreadyCancelled() public {
        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Cancel the request
        skip(SUBSCRIPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Verify request was cancelled
        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(cancelledRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // Try to reject it (in rejectRequests) - should skip (continue in loop) without reverting
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;
        // This tests the _checkValidRequest false path for non-pending status in _processRejected
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify request is still cancelled (status unchanged)
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    // ============================================================================
    // Batch Processing with Skip Conditions (Branch Coverage)
    // ============================================================================

    /// @notice Test that _processApproved skips invalid requests and processes valid ones in batch
    /// @dev This explicitly tests the continue statements in _processApproved loop
    function testProcessApprovedSubscriptionBatchWithSkips() public {
        // Create multiple requests with different states
        uint256 validRequestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        uint256 processedRequestId = _testRequestProcessing(true, bob, _usdcAmount(100), SHARES_PRICE, true);
        uint256 rejectedRequestId = _testRequestProcessing(true, carol, _usdcAmount(100), SHARES_PRICE, false);

        // Reject one request
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = rejectedRequestId;
        kpkSharesContract.processRequests(new uint256[](0), rejectRequests, address(usdc), SHARES_PRICE);

        // Cancel one request (need to wait for TTL)
        uint256 cancelledRequestId = _testRequestProcessing(true, alice, _usdcAmount(50), SHARES_PRICE, false);
        skip(SUBSCRIPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(cancelledRequestId);

        // Create a request with mismatched asset (request for otherAsset, but we'll process with USDC)
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));
        otherAsset.mint(address(bob), _sharesAmount(10_000));
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(otherAsset), true, true, true);
        vm.prank(safe);
        otherAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Create a subscription request for otherAsset
        uint256 amount = _usdcAmount(100);
        uint256 minSharesOut = kpkSharesContract.previewSubscription(amount, SHARES_PRICE, address(otherAsset));
        vm.prank(bob);
        otherAsset.approve(address(kpkSharesContract), amount);
        vm.prank(bob);
        uint256 mismatchedAssetRequestId =
            kpkSharesContract.requestSubscription(amount, minSharesOut, address(otherAsset), bob);

        // Process batch with mixed valid/invalid requests
        // Should skip: processedRequestId (already processed), rejectedRequestId (already rejected),
        //              cancelledRequestId (cancelled), mismatchedAssetRequestId (wrong asset - otherAsset vs USDC)
        // Should process: validRequestId
        uint256[] memory approveRequests = new uint256[](5);
        approveRequests[0] = validRequestId;
        approveRequests[1] = processedRequestId; // Should skip (already processed)
        approveRequests[2] = rejectedRequestId; // Should skip (already rejected)
        approveRequests[3] = cancelledRequestId; // Should skip (cancelled)
        approveRequests[4] = mismatchedAssetRequestId; // Should skip (mismatched asset - request is for otherAsset, processing with USDC)

        uint256 aliceBalanceBefore = kpkSharesContract.balanceOf(alice);
        // Process with USDC - mismatchedAssetRequestId should be skipped (it's for otherAsset)
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify only validRequestId was processed
        assertGt(kpkSharesContract.balanceOf(alice), aliceBalanceBefore, "Valid request should be processed");

        IkpkShares.UserRequest memory validRequest = kpkSharesContract.getRequest(validRequestId);
        assertEq(
            uint8(validRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.PROCESSED),
            "Valid request should be processed"
        );

        IkpkShares.UserRequest memory processedRequest = kpkSharesContract.getRequest(processedRequestId);
        assertEq(
            uint8(processedRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.PROCESSED),
            "Already processed request should remain processed"
        );

        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(rejectedRequestId);
        assertEq(
            uint8(rejectedRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.REJECTED),
            "Rejected request should remain rejected"
        );

        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(cancelledRequestId);
        assertEq(
            uint8(cancelledRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.CANCELLED),
            "Cancelled request should remain cancelled"
        );

        IkpkShares.UserRequest memory mismatchedRequest = kpkSharesContract.getRequest(mismatchedAssetRequestId);
        assertEq(
            uint8(mismatchedRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.PENDING),
            "Mismatched asset request should remain pending"
        );
    }

    /// @notice Test that _processRejected skips invalid requests in batch
    /// @dev This explicitly tests the continue statements in _processRejected loop
    function testProcessRejectedSubscriptionBatchWithSkips() public {
        // Create multiple requests with different states
        uint256 validRequestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        uint256 processedRequestId = _testRequestProcessing(true, bob, _usdcAmount(100), SHARES_PRICE, true);
        uint256 rejectedRequestId = _testRequestProcessing(true, carol, _usdcAmount(100), SHARES_PRICE, false);

        // Reject one request first
        vm.prank(ops);
        uint256[] memory rejectRequests1 = new uint256[](1);
        rejectRequests1[0] = rejectedRequestId;
        kpkSharesContract.processRequests(new uint256[](0), rejectRequests1, address(usdc), SHARES_PRICE);

        // Cancel one request
        uint256 cancelledRequestId = _testRequestProcessing(true, alice, _usdcAmount(50), SHARES_PRICE, false);
        skip(SUBSCRIPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(cancelledRequestId);

        // Create a request with mismatched asset (request for otherAsset, but we'll process with USDC)
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));
        otherAsset.mint(address(bob), _sharesAmount(10_000));
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(otherAsset), true, true, true);
        vm.prank(safe);
        otherAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Create a subscription request for otherAsset
        uint256 amount = _usdcAmount(100);
        uint256 minSharesOut = kpkSharesContract.previewSubscription(amount, SHARES_PRICE, address(otherAsset));
        vm.prank(bob);
        otherAsset.approve(address(kpkSharesContract), amount);
        vm.prank(bob);
        uint256 mismatchedAssetRequestId =
            kpkSharesContract.requestSubscription(amount, minSharesOut, address(otherAsset), bob);

        // Process batch with mixed valid/invalid requests for rejection
        // Should skip: processedRequestId (already processed), rejectedRequestId (already rejected),
        //              cancelledRequestId (cancelled), mismatchedAssetRequestId (wrong asset - otherAsset vs USDC)
        // Should reject: validRequestId
        vm.prank(ops);
        uint256[] memory rejectRequests2 = new uint256[](5);
        rejectRequests2[0] = validRequestId;
        rejectRequests2[1] = processedRequestId; // Should skip (already processed)
        rejectRequests2[2] = rejectedRequestId; // Should skip (already rejected)
        rejectRequests2[3] = cancelledRequestId; // Should skip (cancelled)
        rejectRequests2[4] = mismatchedAssetRequestId; // Should skip (mismatched asset - request is for otherAsset, processing with USDC)

        kpkSharesContract.processRequests(new uint256[](0), rejectRequests2, address(usdc), SHARES_PRICE);

        // Verify only validRequestId was rejected
        IkpkShares.UserRequest memory validRequest = kpkSharesContract.getRequest(validRequestId);
        assertEq(
            uint8(validRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.REJECTED),
            "Valid request should be rejected"
        );

        IkpkShares.UserRequest memory processedRequest = kpkSharesContract.getRequest(processedRequestId);
        assertEq(
            uint8(processedRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.PROCESSED),
            "Already processed request should remain processed"
        );

        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(rejectedRequestId);
        assertEq(
            uint8(rejectedRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.REJECTED),
            "Rejected request should remain rejected"
        );

        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(cancelledRequestId);
        assertEq(
            uint8(cancelledRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.CANCELLED),
            "Cancelled request should remain cancelled"
        );

        IkpkShares.UserRequest memory mismatchedRequest = kpkSharesContract.getRequest(mismatchedAssetRequestId);
        assertEq(
            uint8(mismatchedRequest.requestStatus),
            uint8(IkpkShares.RequestStatus.PENDING),
            "Mismatched asset request should remain pending"
        );
    }

    // ============================================================================
    // Request Expiry Tests
    // ============================================================================

    function testExpiredSubscriptionRequestAutoRejection() public {
        // Create subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Get the request to check expiryAt and asset amount
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        uint64 expiryAt = request.expiryAt;
        uint256 assetAmount = request.assetAmount;

        // Fast forward past MAX_TTL (7 days)
        skip(7 days + 1);

        // Store initial balance to verify refund (assets are in contract at this point)
        uint256 initialBalance = usdc.balanceOf(alice);

        // Process request - should be automatically rejected
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        vm.expectEmit(true, true, true, true);
        emit IkpkShares.SubscriptionRequestExpired(requestId, expiryAt);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify request was rejected
        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(rejectedRequest.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));

        // Verify assets were refunded
        uint256 finalBalance = usdc.balanceOf(alice);
        assertEq(finalBalance, initialBalance + assetAmount);
    }

    // ============================================================================
    // TTL Edge Cases Tests
    // ============================================================================

    function testSubscriptionRequestTtlMaximumLimit() public {
        // Test that TTL is capped at 7 days maximum
        uint64 maxTtl = 7 days;
        uint64 largeTtl = 365 days; // 1 year

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(largeTtl);

        // Should be capped at 7 days
        assertEq(kpkSharesContract.subscriptionRequestTtl(), maxTtl);

        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire (7 days + 1 second)
        skip(maxTtl + 1);

        // Should be able to cancel after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    // ============================================================================
    // Asset Refund Logic Tests (Coverage for lines 828-830)
    // ============================================================================

    // ============================================================================
    // Update Request TTL Edge Case Tests (Coverage for line 776)
    // ============================================================================

    // ============================================================================
    // Specific Line Coverage Tests
    // ============================================================================

    function testCancelSubscriptionRequestNotPastTtlLine254() public {
        // Test specifically for line 254: RequestNotPastTtl revert
        // This line: if (block.timestamp <= request.timestamp + depositRequestTtl) { revert RequestNotPastTtl(); }

        uint64 ttl = 1 hours;
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(ttl);

        // Create a subscription request directly (not using helper function)
        usdc.mint(alice, _usdcAmount(100));
        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), _usdcAmount(100));
        uint256 requestId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // Immediately try to cancel - should revert with RequestNotPastTtl (line 254)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPastTtl.selector));
        kpkSharesContract.cancelSubscription(requestId);

        // Wait exactly TTL - at exactly TTL, block.timestamp == request.timestamp + subscriptionRequestTtl
        // The condition is block.timestamp < request.timestamp + subscriptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        skip(ttl);
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Verify the request was cancelled
        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(cancelledRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testCancelSubscriptionRequestNotPastTtlLine254EdgeCase() public {
        // Test specifically for line 254 with a very short TTL to ensure we hit the exact condition
        // This line: if (block.timestamp <= request.timestamp + depositRequestTtl) { revert RequestNotPastTtl(); }

        uint64 veryShortTtl = 1; // 1 second TTL
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(veryShortTtl);

        // Create a subscription request
        usdc.mint(alice, _usdcAmount(100));
        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), _usdcAmount(100));
        uint256 requestId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // Try to cancel immediately - should revert with RequestNotPastTtl (line 254)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPastTtl.selector));
        kpkSharesContract.cancelSubscription(requestId);

        // Wait exactly 1 second (TTL) - at exactly TTL, block.timestamp == request.timestamp + subscriptionRequestTtl
        // The condition is block.timestamp < request.timestamp + subscriptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        skip(1);
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Verify the request was cancelled
        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(cancelledRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testValidateDepositRequestReturnTrueLines967_968() public {
        // Test specifically for lines 967-968: return true in _validateDepositRequest
        // This function is called during deposit processing, so we need to trigger it

        // Create a valid deposit request
        usdc.mint(alice, _usdcAmount(100));
        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), _usdcAmount(100));
        uint256 requestId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // Get the request to verify it's valid
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);

        // Verify the request meets the validation criteria (lines 967-968)
        assertTrue(request.investor != address(0), "Investor should not be zero address");
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING), "Request should be pending");

        // Process the request to trigger _validateDepositRequest internally
        // This will call _validateDepositRequest and should return true (lines 967-968)
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Check that the request was processed successfully (which means validation passed and returned true)
        IkpkShares.UserRequest memory processedRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(processedRequest.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));

        // Also test with a rejected request to ensure the validation path is covered
        usdc.mint(bob, _usdcAmount(50));
        vm.startPrank(bob);
        usdc.approve(address(kpkSharesContract), _usdcAmount(50));
        uint256 rejectRequestId = kpkSharesContract.requestSubscription(
            _usdcAmount(50),
            kpkSharesContract.assetsToShares(_usdcAmount(50), SHARES_PRICE, address(usdc)),
            address(usdc),
            bob
        );
        vm.stopPrank();

        // Reject the request - this also triggers _validateDepositRequest
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = rejectRequestId;
        kpkSharesContract.processRequests(new uint256[](0), rejectRequests, address(usdc), SHARES_PRICE);

        // Check that the request was rejected (which means validation passed and returned true)
        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(rejectRequestId);
        assertEq(uint8(rejectedRequest.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));
    }

    // ============================================================================
    // TTL Edge Case Tests (Coverage for line 254)
    // ============================================================================

    function testSubscriptionRequestTtlExactBoundary() public {
        // Test the exact boundary case where block.timestamp == request.timestamp + depositRequestTtl
        uint64 edgeTtl = 1 hours;

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(edgeTtl);

        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Wait exactly to the TTL boundary
        skip(edgeTtl);

        // At exactly TTL boundary, block.timestamp == request.timestamp + subscriptionRequestTtl
        // The condition is block.timestamp < request.timestamp + subscriptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testSubscriptionRequestTtlEdgeCase() public {
        // Test TTL edge case where timestamp + TTL equals block.timestamp
        uint64 edgeTtl = 1 hours;

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(edgeTtl);

        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Wait exactly to the TTL boundary
        skip(edgeTtl);

        // At exactly TTL boundary, block.timestamp == request.timestamp + subscriptionRequestTtl
        // The condition is block.timestamp < request.timestamp + subscriptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Verify the request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testSubscriptionRequestTtlWithVerySmallValue() public {
        // Test with very small TTL value
        uint64 smallTtl = 1; // 1 second

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(smallTtl);

        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire (1 second + 1)
        skip(smallTtl + 1);

        // Should be able to cancel after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    // ============================================================================
    // TTL Validation Edge Cases Tests
    // ============================================================================

    function testSubscriptionRequestTtlValidationEdgeCases() public {
        // Test TTL validation edge cases
        uint64 edgeTtl = 1 hours;

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(edgeTtl);

        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Try to cancel before TTL expires - should revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPastTtl.selector));
        kpkSharesContract.cancelSubscription(requestId);

        // Wait for TTL to expire exactly
        skip(edgeTtl);

        // At exactly TTL expiration, block.timestamp == request.timestamp + subscriptionRequestTtl
        // The condition is block.timestamp < request.timestamp + subscriptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testSubscriptionRequestTtlWithZeroValue() public {
        // Test TTL validation with zero value
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.setSubscriptionRequestTtl(0);
    }

    function testSubscriptionRequestTtlWithVeryLargeValue() public {
        // Test TTL validation with very large value (should be capped at 7 days)
        uint64 largeTtl = 365 days; // 1 year
        uint64 expectedTtl = 7 days; // Contract caps at 7 days

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(largeTtl);

        assertEq(kpkSharesContract.subscriptionRequestTtl(), expectedTtl);

        // Create a subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire (7 days + 1)
        skip(expectedTtl + 1);

        // Should be able to cancel after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    // ============================================================================
    // Request Processing Edge Cases Tests
    // ============================================================================

    function testProcessSubscriptionRequestsWithComplexTtlScenarios() public {
        // Test complex TTL scenarios with multiple requests
        uint64 shortTtl = 1 hours;
        uint64 longTtl = 3 days;

        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(shortTtl);

        // Create multiple subscription requests
        uint256 requestId1 = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        uint256 requestId2 = _testRequestProcessing(true, bob, _usdcAmount(200), SHARES_PRICE, false);

        // Wait for first TTL to expire
        skip(shortTtl + 1);

        // Cancel first request after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId1);

        // Change TTL to longer value
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(longTtl);

        // Create another request with new TTL
        uint256 requestId3 = _testRequestProcessing(true, carol, _usdcAmount(300), SHARES_PRICE, false);

        // Wait for second TTL to expire
        skip(longTtl + 1);

        // Cancel second request after TTL expires
        vm.prank(bob);
        kpkSharesContract.cancelSubscription(requestId2);

        // Cancel third request after TTL expires
        vm.prank(carol);
        kpkSharesContract.cancelSubscription(requestId3);

        // Check that all requests were cancelled
        IkpkShares.UserRequest memory request1 = kpkSharesContract.getRequest(requestId1);
        IkpkShares.UserRequest memory request2 = kpkSharesContract.getRequest(requestId2);
        IkpkShares.UserRequest memory request3 = kpkSharesContract.getRequest(requestId3);
        assertEq(uint8(request1.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
        assertEq(uint8(request2.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
        assertEq(uint8(request3.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testRequestProcessingEdgeCases() public {
        // Test request processing edge cases to cover uncovered branches

        // Ensure users have sufficient USDC balance and allowance
        usdc.mint(alice, _usdcAmount(1000));
        usdc.mint(bob, _usdcAmount(1000));
        usdc.mint(carol, _usdcAmount(1000));
        usdc.mint(ops, _usdcAmount(1000));

        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(carol);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(ops);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        vm.stopPrank();

        // Test with very small amounts
        uint256 requestId1 = _testRequestProcessing(true, alice, _usdcAmount(1), SHARES_PRICE, false);

        // Test with large amounts (but within user balance)
        uint256 requestId2 = _testRequestProcessing(true, bob, _usdcAmount(500), SHARES_PRICE, false);

        // Test with edge case prices (but not extreme)
        uint256 requestId3 = _testRequestProcessing(true, carol, _usdcAmount(100), 1e12, false);

        // Test with high price (but not maximum)
        uint256 requestId4 = _testRequestProcessing(true, ops, _usdcAmount(100), 1e13, false);

        // Process all requests
        uint256[] memory approveRequests = new uint256[](4);
        approveRequests[0] = requestId1;
        approveRequests[1] = requestId2;
        approveRequests[2] = requestId3;
        approveRequests[3] = requestId4;

        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Check that all requests were processed
        IkpkShares.UserRequest memory request1 = kpkSharesContract.getRequest(requestId1);
        IkpkShares.UserRequest memory request2 = kpkSharesContract.getRequest(requestId2);
        IkpkShares.UserRequest memory request3 = kpkSharesContract.getRequest(requestId3);
        IkpkShares.UserRequest memory request4 = kpkSharesContract.getRequest(requestId4);
        assertEq(uint8(request1.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        assertEq(uint8(request2.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        assertEq(uint8(request3.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        assertEq(uint8(request4.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
    }

    // ============================================================================
    // Subscription Cancellation Tests
    // ============================================================================

    function testCancelSubscriptionRequest() public {
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        uint256 initialBalance = usdc.balanceOf(alice);

        // Skip past the TTL so cancellation is allowed
        skip(SUBSCRIPTION_REQUEST_TTL + 1);

        vm.startPrank(alice);
        kpkSharesContract.cancelSubscription(requestId);
        vm.stopPrank();

        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(cancelledRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // Check that assets were returned
        uint256 finalBalance = usdc.balanceOf(alice);
        assertGt(finalBalance, initialBalance);
    }

    function testCancelSubscriptionRequestWithDifferentRequester() public {
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Skip past the TTL so cancellation is allowed
        skip(SUBSCRIPTION_REQUEST_TTL + 1);

        // Try to cancel with different requester
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.cancelSubscription(requestId);
        vm.stopPrank();
    }

    function testCancelSubscriptionByReceiver() public {
        // Create subscription with receiver != investor
        usdc.mint(alice, _usdcAmount(100));
        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), _usdcAmount(100));
        uint256 requestId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            bob // receiver is different from investor (alice)
        );
        vm.stopPrank();

        // Wait for TTL to expire
        skip(SUBSCRIPTION_REQUEST_TTL + 1);

        // Store initial balance
        uint256 initialBalance = usdc.balanceOf(alice);

        // Cancel as receiver (bob) - should succeed
        vm.prank(bob);
        kpkSharesContract.cancelSubscription(requestId);

        // Verify request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // Verify assets were returned to investor (alice), not receiver
        uint256 finalBalance = usdc.balanceOf(alice);
        assertEq(finalBalance, initialBalance + _usdcAmount(100));
    }

    function testCancelSubscriptionByUnauthorizedUser() public {
        // Create subscription request
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire
        skip(SUBSCRIPTION_REQUEST_TTL + 1);

        // Try to cancel as unauthorized user (carol, not investor or receiver)
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.cancelSubscription(requestId);
    }

    function testCancelSubscriptionRequestAfterProcessing() public {
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, true);

        // Skip past the TTL so cancellation timing is not an issue
        skip(SUBSCRIPTION_REQUEST_TTL + 1);

        // Try to cancel after processing
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPending.selector));
        kpkSharesContract.cancelSubscription(requestId);
        vm.stopPrank();
    }

    function testCancelSubscriptionRequestWithUnknownRequest() public {
        // Try to cancel a non-existent request
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPending.selector));
        kpkSharesContract.cancelSubscription(999);
        vm.stopPrank();
    }

    // ============================================================================
    // Edge Cases and Integration Tests
    // ============================================================================

    function testMultipleSubscriptionRequestsFromSameUser() public {
        // Create multiple requests from the same user
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _testRequestProcessing(true, alice, _usdcAmount(50), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(true, alice, _usdcAmount(75), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(true, alice, _usdcAmount(25), SHARES_PRICE, false);

        // Process all requests
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(requestIds, rejectRequests, address(usdc), SHARES_PRICE);

        // Check total shares
        uint256 totalShares = kpkSharesContract.balanceOf(alice);
        assertGt(totalShares, 0);
    }

    function testSubscriptionRequestWithVeryLargeAmount() public {
        uint256 largeAmount = _usdcAmount(1_000_000); // 1M USDC

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(
            largeAmount,
            kpkSharesContract.assetsToShares(largeAmount, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.assetAmount, largeAmount);
    }

    function testSubscriptionRequestWithVerySmallAmount() public {
        uint256 smallAmount = 1; // 1 wei

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(
            smallAmount,
            kpkSharesContract.assetsToShares(smallAmount, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.assetAmount, smallAmount);
    }
}
