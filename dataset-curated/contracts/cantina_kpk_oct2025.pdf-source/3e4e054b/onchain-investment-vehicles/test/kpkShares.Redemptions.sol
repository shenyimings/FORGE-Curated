// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Tests for kpkShares redemption functionality
contract kpkSharesRedemptionsTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Basic Redemption Request Tests
    // ============================================================================

    function testRequestRedemption() public {
        uint256 shares = _sharesAmount(100);
        uint256 price = SHARES_PRICE;

        // First create shares for testing
        _createSharesForTesting(alice, shares);

        // Calculate expected assets using sharesToAssets
        uint256 assetsOut = kpkSharesContract.sharesToAssets(shares, price, address(usdc));

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);
        vm.stopPrank();

        assertEq(requestId, 2);

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestType), uint8(IkpkShares.RequestType.REDEMPTION));
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING));
        assertEq(request.asset, address(usdc));
        assertEq(request.sharesAmount, shares);
        assertEq(request.receiver, alice);
        assertEq(request.investor, alice);
        assertEq(request.timestamp, block.timestamp);
    }

    function testRequestRedemptionWithDifferentInvestor() public {
        uint256 shares = _sharesAmount(100);
        uint256 price = SHARES_PRICE;

        // First create shares for testing for both alice and bob
        _createSharesForTesting(alice, shares);
        _createSharesForTesting(bob, shares);

        // Bob needs to approve Alice to spend his shares
        vm.prank(bob);
        kpkSharesContract.approve(alice, shares);

        // Calculate expected assets using sharesToAssets
        uint256 assetsOut = kpkSharesContract.sharesToAssets(shares, price, address(usdc));

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(
            shares,
            assetsOut,
            address(usdc),
            bob // Different investor
        );
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.investor, alice); // Alice is the one making the request (msg.sender)
        assertEq(request.receiver, bob); // Bob is the receiver where assets will be sent
    }

    function testRequestRedemptionWithUnapprovedAsset() public {
        uint256 shares = _sharesAmount(100);

        // First create shares for testing
        _createSharesForTesting(alice, shares);

        // Create a new token that's not approved
        Mock_ERC20 unapprovedToken = new Mock_ERC20("UNAPPROVED", 18);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAnApprovedAsset.selector));
        kpkSharesContract.requestRedemption(shares, 1, address(unapprovedToken), alice);
        vm.stopPrank();
    }

    function testRequestRedemptionWithZeroShares() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.requestRedemption(0, 0, address(usdc), alice);
        vm.stopPrank();
    }

    function testRequestRedemptionWithZeroPrice() public {
        uint256 shares = _sharesAmount(100);

        // First create shares for testing
        _createSharesForTesting(alice, shares);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.requestRedemption(shares, 0, address(usdc), alice);
        vm.stopPrank();
    }

    function testRequestRedemptionWithZeroAddressInvestor() public {
        uint256 shares = _sharesAmount(100);

        // First create shares for testing
        _createSharesForTesting(alice, shares);

        uint256 assetsOut = kpkSharesContract.sharesToAssets(shares, SHARES_PRICE, address(usdc));

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), address(0));
        vm.stopPrank();
    }

    function testRequestRedemptionWithInsufficientShares() public {
        uint256 shares = _sharesAmount(100);
        uint256 assets = _usdcAmount(100);

        // Create fewer shares than requested
        _createSharesForTesting(alice, shares / 2);

        vm.startPrank(alice);
        vm.expectRevert(); // Should revert due to insufficient balance
        kpkSharesContract.requestRedemption(shares, assets, address(usdc), alice);
        vm.stopPrank();
    }

    // ============================================================================
    // Redemption Preview Tests
    // ============================================================================

    function testPreviewRedemption() public view {
        uint256 shares = _sharesAmount(100);
        uint256 price = SHARES_PRICE;

        uint256 assets = kpkSharesContract.previewRedemption(shares, price, address(usdc));

        // Verify that assets are calculated correctly (should be > 0 for valid shares)
        assertGt(assets, 0);

        // Asset amount should be calculated using the contract's sharesToAssets function (accounting for fees)
        uint256 redemptionFee = (shares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 netShares = shares - redemptionFee;
        uint256 expectedAssets = kpkSharesContract.sharesToAssets(netShares, price, address(usdc));
        assertEq(assets, expectedAssets);
    }

    function testPreviewRedemptionWithUnapprovedAsset() public {
        uint256 shares = _sharesAmount(100);
        uint256 price = SHARES_PRICE;

        // This should revert as previewRedemption calls sharesToAssets which checks canRedeem
        // sharesToAssets throws UnredeemableAsset() for assets that can't be redeemed
        Mock_ERC20 unapprovedToken = new Mock_ERC20("UNAPPROVED", 18);

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.UnredeemableAsset.selector));
        kpkSharesContract.previewRedemption(shares, price, address(unapprovedToken));
    }

    function testPreviewRedemptionWithDifferentPrices() public view {
        uint256 shares = _sharesAmount(100);

        // Test with different prices
        uint256[] memory prices = new uint256[](3);
        prices[0] = SHARES_PRICE; // 1:1
        prices[1] = 2e7; // 0.2:1
        prices[2] = 1e9; // 10:1

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 assets = kpkSharesContract.previewRedemption(shares, prices[i], address(usdc));

            // Account for redemption fees
            uint256 redemptionFee = (shares * kpkSharesContract.redemptionFeeRate()) / 10000;
            uint256 netShares = shares - redemptionFee;
            uint256 expectedAssets = kpkSharesContract.sharesToAssets(netShares, prices[i], address(usdc));
            assertEq(assets, expectedAssets);
        }
    }

    function testPreviewRedemptionWithZeroPrice() public {
        // First, process a request to set last settled price
        uint256 depositId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now call previewRedemption with sharesPrice = 0
        // Should use last settled price
        uint256 shares = _sharesAmount(100);
        uint256 assets = kpkSharesContract.previewRedemption(shares, 0, address(usdc));

        // Should calculate using last settled price (SHARES_PRICE)
        uint256 redemptionFee = (shares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 netShares = shares - redemptionFee;
        uint256 expectedAssets = kpkSharesContract.sharesToAssets(netShares, SHARES_PRICE, address(usdc));
        assertEq(assets, expectedAssets);
    }

    function testPreviewRedemptionNoStoredPrice() public {
        // Call previewRedemption with sharesPrice = 0
        // Before any processing (no stored price exists)
        uint256 shares = _sharesAmount(100);

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NoStoredPrice.selector));
        kpkSharesContract.previewRedemption(shares, 0, address(usdc));
    }

    /// @notice Test previewRedemption with both zero and non-zero price in same test
    /// @dev This explicitly tests both branches of the sharesPrice == 0 condition (line 309)
    function testPreviewRedemptionBothBranches() public {
        uint256 shares = _sharesAmount(100);

        // First, test with non-zero price (sharesPrice != 0 branch)
        uint256 nonZeroPrice = SHARES_PRICE;
        uint256 assets1 = kpkSharesContract.previewRedemption(shares, nonZeroPrice, address(usdc));
        uint256 redemptionFee = (shares * kpkSharesContract.redemptionFeeRate()) / 10000;
        uint256 netShares = shares - redemptionFee;
        uint256 expectedAssets1 = kpkSharesContract.sharesToAssets(netShares, nonZeroPrice, address(usdc));
        assertEq(assets1, expectedAssets1, "Non-zero price branch should work correctly");

        // Process a request to set last settled price
        uint256 depositId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now test with zero price (sharesPrice == 0 branch, uses last settled price)
        uint256 assets2 = kpkSharesContract.previewRedemption(shares, 0, address(usdc));
        uint256 expectedAssets2 = kpkSharesContract.sharesToAssets(netShares, SHARES_PRICE, address(usdc));
        assertEq(assets2, expectedAssets2, "Zero price branch should use last settled price");

        // Both should give same result since we used same price
        assertEq(assets1, assets2, "Both branches should give same result with same underlying price");
    }

    // ============================================================================
    // Redemption Processing Tests
    // ============================================================================

    function testProcessRedemptionRequests() public {
        // Create multiple redemption requests
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _testRequestProcessing(false, alice, _sharesAmount(50), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(false, bob, _sharesAmount(75), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(false, carol, _sharesAmount(25), SHARES_PRICE, false);

        // Process all requests
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](3);
        approveRequests[0] = requestIds[0];
        approveRequests[1] = requestIds[1];
        approveRequests[2] = requestIds[2];

        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Check that all requests were processed
        for (uint256 i = 0; i < requestIds.length; i++) {
            IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestIds[i]);
            assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
        }

        // Check that assets were transferred
        assertGt(usdc.balanceOf(alice), 0);
        assertGt(usdc.balanceOf(bob), 0);
        assertGt(usdc.balanceOf(carol), 0);
    }

    function testProcessRedemptionRequestsWithRejections() public {
        // Create multiple redemption requests
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _testRequestProcessing(false, alice, _sharesAmount(50), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(false, bob, _sharesAmount(75), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(false, carol, _sharesAmount(25), SHARES_PRICE, false);

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

    function testProcessRedemptionRequestsUnauthorized() public {
        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Try to process without operator role
        vm.prank(alice);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
    }

    function testProcessRedemptionRequestsWithEmptyArrays() public {
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

    function testProcessRedemptionRequestWithMismatchedAsset() public {
        // Create redemption request for USDC
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Create a different asset
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));

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

    function testProcessAlreadyProcessedRedemptionRequest() public {
        // Create and process a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, true);

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

    function testProcessAlreadyRejectedRedemptionRequest() public {
        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

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

    function testProcessAlreadyCancelledRedemptionRequest() public {
        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Cancel the request
        skip(REDEMPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

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

    function testProcessRejectedRedemptionSkipsMismatchedAsset() public {
        // Create redemption request for USDC
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Create a different asset
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));

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

    function testProcessRejectedRedemptionSkipsAlreadyProcessed() public {
        // Create and process a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, true);

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

    function testProcessRejectedRedemptionSkipsAlreadyRejected() public {
        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

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

    function testProcessRejectedRedemptionSkipsAlreadyCancelled() public {
        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Cancel the request
        skip(REDEMPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

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

    function testCheckValidRequestWithNonPendingStatusRedemption() public {
        // Create and process a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, true);

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

    // ============================================================================
    // Batch Processing with Skip Conditions (Branch Coverage)
    // ============================================================================

    /// @notice Test that _processApproved skips invalid requests and processes valid ones in batch
    /// @dev This explicitly tests the continue statements in _processApproved loop
    function testProcessApprovedRedemptionBatchWithSkips() public {
        // Create multiple requests with different states
        uint256 validRequestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);
        uint256 processedRequestId = _testRequestProcessing(false, bob, _sharesAmount(100), SHARES_PRICE, true);
        uint256 rejectedRequestId = _testRequestProcessing(false, carol, _sharesAmount(100), SHARES_PRICE, false);

        // Reject one request
        vm.prank(ops);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = rejectedRequestId;
        kpkSharesContract.processRequests(new uint256[](0), rejectRequests, address(usdc), SHARES_PRICE);

        // Cancel one request (need to wait for TTL)
        uint256 cancelledRequestId = _testRequestProcessing(false, alice, _sharesAmount(50), SHARES_PRICE, false);
        skip(REDEMPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(cancelledRequestId);

        // Create a request with mismatched asset (request for otherAsset, but we'll process with USDC)
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(otherAsset), true, true, true);
        vm.prank(safe);
        otherAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Create shares for bob first
        uint256 sharesForBob = _sharesAmount(100);
        _createSharesForTesting(bob, sharesForBob);

        // Create a redemption request for otherAsset
        uint256 minAssetsOut = kpkSharesContract.previewRedemption(sharesForBob, SHARES_PRICE, address(otherAsset));
        vm.prank(bob);
        kpkSharesContract.approve(address(kpkSharesContract), sharesForBob);
        vm.prank(bob);
        uint256 mismatchedAssetRequestId =
            kpkSharesContract.requestRedemption(sharesForBob, minAssetsOut, address(otherAsset), bob);

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

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        // Process with USDC - mismatchedAssetRequestId should be skipped (it's for otherAsset)
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify only validRequestId was processed
        assertGt(usdc.balanceOf(alice), aliceBalanceBefore, "Valid request should be processed");

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
    function testProcessRejectedRedemptionBatchWithSkips() public {
        // Create multiple requests with different states
        uint256 validRequestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);
        uint256 processedRequestId = _testRequestProcessing(false, bob, _sharesAmount(100), SHARES_PRICE, true);
        uint256 rejectedRequestId = _testRequestProcessing(false, carol, _sharesAmount(100), SHARES_PRICE, false);

        // Reject one request first
        vm.prank(ops);
        uint256[] memory rejectRequests1 = new uint256[](1);
        rejectRequests1[0] = rejectedRequestId;
        kpkSharesContract.processRequests(new uint256[](0), rejectRequests1, address(usdc), SHARES_PRICE);

        // Cancel one request
        uint256 cancelledRequestId = _testRequestProcessing(false, alice, _sharesAmount(50), SHARES_PRICE, false);
        skip(REDEMPTION_REQUEST_TTL + 1);
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(cancelledRequestId);

        // Create a request with mismatched asset (request for otherAsset, but we'll process with USDC)
        Mock_ERC20 otherAsset = new Mock_ERC20("OTHER", 18);
        otherAsset.mint(address(safe), _sharesAmount(100_000));
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(otherAsset), true, true, true);
        vm.prank(safe);
        otherAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Create shares for bob first
        uint256 sharesForBob = _sharesAmount(100);
        _createSharesForTesting(bob, sharesForBob);

        // Create a redemption request for otherAsset
        uint256 minAssetsOut = kpkSharesContract.previewRedemption(sharesForBob, SHARES_PRICE, address(otherAsset));
        vm.prank(bob);
        kpkSharesContract.approve(address(kpkSharesContract), sharesForBob);
        vm.prank(bob);
        uint256 mismatchedAssetRequestId =
            kpkSharesContract.requestRedemption(sharesForBob, minAssetsOut, address(otherAsset), bob);

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

    function testExpiredRedemptionRequestAutoRejection() public {
        // Create redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Get the request to check expiryAt and shares amount
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        uint64 expiryAt = request.expiryAt;
        uint256 sharesAmount = request.sharesAmount;

        // Fast forward past MAX_TTL (7 days)
        skip(7 days + 1);

        // Store initial balance to verify refund (shares are in escrow at this point)
        uint256 initialShares = kpkSharesContract.balanceOf(alice);

        // Process request - should be automatically rejected
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        vm.expectEmit(true, true, true, true);
        emit IkpkShares.RedemptionRequestExpired(requestId, expiryAt);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Verify request was rejected
        IkpkShares.UserRequest memory rejectedRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(rejectedRequest.requestStatus), uint8(IkpkShares.RequestStatus.REJECTED));

        // Verify shares were returned from escrow
        uint256 finalShares = kpkSharesContract.balanceOf(alice);
        assertEq(finalShares, initialShares + sharesAmount);
    }

    // ============================================================================
    // Redemption Update Tests
    // ============================================================================

    // ============================================================================
    // Redemption Cancellation Tests
    // ============================================================================

    function testCancelRedemptionRequest() public {
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire before cancelling
        skip(REDEMPTION_REQUEST_TTL + 1);

        uint256 initialShares = kpkSharesContract.balanceOf(alice);

        vm.startPrank(alice);
        kpkSharesContract.cancelRedemption(requestId);
        vm.stopPrank();

        IkpkShares.UserRequest memory cancelledRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(cancelledRequest.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // Check that shares were returned
        uint256 finalShares = kpkSharesContract.balanceOf(alice);
        assertGe(finalShares, initialShares);
    }

    function testCancelRedemptionRequestWithDifferentRequester() public {
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire before cancelling
        skip(REDEMPTION_REQUEST_TTL + 1);

        // Try to cancel with different requester
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.cancelRedemption(requestId);
        vm.stopPrank();
    }

    function testCancelRedemptionByReceiver() public {
        // Create shares first
        _createSharesForTesting(alice, _sharesAmount(100));

        // Create redemption with receiver != investor
        vm.startPrank(alice);
        kpkSharesContract.approve(address(kpkSharesContract), _sharesAmount(100));
        uint256 requestId = kpkSharesContract.requestRedemption(
            _sharesAmount(100),
            kpkSharesContract.sharesToAssets(_sharesAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            bob // receiver is different from investor (alice)
        );
        vm.stopPrank();

        // Wait for TTL to expire
        skip(REDEMPTION_REQUEST_TTL + 1);

        // Store initial balance
        uint256 initialShares = kpkSharesContract.balanceOf(alice);

        // Cancel as receiver (bob) - should succeed
        vm.prank(bob);
        kpkSharesContract.cancelRedemption(requestId);

        // Verify request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));

        // Verify shares were returned to investor (alice), not receiver
        uint256 finalShares = kpkSharesContract.balanceOf(alice);
        assertEq(finalShares, initialShares + _sharesAmount(100));
    }

    function testCancelRedemptionByUnauthorizedUser() public {
        // Create redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire
        skip(REDEMPTION_REQUEST_TTL + 1);

        // Try to cancel as unauthorized user (carol, not investor or receiver)
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.cancelRedemption(requestId);
    }

    function testCancelRedemptionRequestAfterProcessing() public {
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, true);

        // Try to cancel after processing
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPending.selector));
        kpkSharesContract.cancelRedemption(requestId);
        vm.stopPrank();
    }

    function testCancelRedemptionRequestWithUnknownRequest() public {
        // Try to cancel a non-existent request
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPending.selector));
        kpkSharesContract.cancelRedemption(999);
        vm.stopPrank();
    }

    // ============================================================================
    // Edge Cases and Integration Tests
    // ============================================================================

    function testMultipleRedemptionRequestsFromSameUser() public {
        // Create multiple requests from the same user
        uint256[] memory requestIds = new uint256[](3);
        requestIds[0] = _testRequestProcessing(false, alice, _sharesAmount(25), SHARES_PRICE, false);
        requestIds[1] = _testRequestProcessing(false, alice, _sharesAmount(50), SHARES_PRICE, false);
        requestIds[2] = _testRequestProcessing(false, alice, _sharesAmount(25), SHARES_PRICE, false);

        // Process all requests
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](3);
        approveRequests[0] = requestIds[0];
        approveRequests[1] = requestIds[1];
        approveRequests[2] = requestIds[2];

        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // Check total assets received
        uint256 totalAssets = usdc.balanceOf(alice);
        assertGt(totalAssets, 0);
    }

    function testRedemptionRequestWithVeryLargeAmount() public {
        uint256 largeShares = _sharesAmount(1_000_000); // 1M shares

        // First create shares for testing
        _createSharesForTesting(alice, largeShares);

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(
            largeShares,
            kpkSharesContract.sharesToAssets(largeShares, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.sharesAmount, largeShares);
    }

    function testRedemptionRequestWithVerySmallAmount() public {
        uint256 smallShares = 1; // 1 wei

        // First create shares for testing - need to create at least 1 share worth of assets
        uint256 minAssets = kpkSharesContract.sharesToAssets(smallShares, SHARES_PRICE, address(usdc));
        if (minAssets == 0) {
            // If 1 wei of shares results in 0 assets, use a larger amount
            smallShares = _sharesAmount(1); // 1 share
        }

        _createSharesForTesting(alice, smallShares);

        vm.startPrank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(
            smallShares,
            kpkSharesContract.sharesToAssets(smallShares, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.sharesAmount, smallShares);
    }

    function testRedemptionRequestWithProxyRequester() public {
        uint256 shares = _sharesAmount(100);
        uint256 price = SHARES_PRICE;

        // First create shares for testing
        _createSharesForTesting(alice, shares);

        // Alice approves ops to spend her shares
        vm.prank(alice);
        kpkSharesContract.approve(ops, shares);

        // Calculate expected assets using sharesToAssets
        uint256 assetsOut = kpkSharesContract.sharesToAssets(shares, price, address(usdc));

        // Ops requests redemption on behalf of alice
        vm.startPrank(ops);
        require(kpkSharesContract.transferFrom(alice, ops, shares), "Transfer failed");
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);
        vm.stopPrank();

        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(request.investor, ops);
        assertEq(request.receiver, alice);
    }

    // ============================================================================
    // TTL Edge Cases Tests
    // ============================================================================

    function testRedemptionRequestTtlMaximumLimit() public {
        // Test that TTL is capped at 7 days maximum
        uint64 maxTtl = 7 days;
        uint64 largeTtl = 365 days; // 1 year

        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(largeTtl);

        // Should be capped at 7 days
        assertEq(kpkSharesContract.redemptionRequestTtl(), maxTtl);

        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire (7 days + 1 second)
        skip(maxTtl + 1);

        // Should be able to cancel after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testRedemptionRequestTtlEdgeCase() public {
        // Test TTL edge case where timestamp + TTL equals block.timestamp
        uint64 edgeTtl = 1 hours;

        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(edgeTtl);

        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait exactly to the TTL boundary
        skip(edgeTtl);

        // At exactly TTL boundary, block.timestamp == request.timestamp + redemptionRequestTtl
        // The condition is block.timestamp < request.timestamp + redemptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

        // Verify the request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testRedemptionRequestTtlWithVerySmallValue() public {
        // Test with very small TTL value
        uint64 smallTtl = 1; // 1 second

        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(smallTtl);

        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire (1 second + 1)
        skip(smallTtl + 1);

        // Should be able to cancel after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    // ============================================================================
    // TTL Validation Edge Cases Tests
    // ============================================================================

    function testRedemptionRequestTtlValidationEdgeCases() public {
        // Test TTL validation edge cases
        uint64 edgeTtl = 1 hours;

        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(edgeTtl);

        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Try to cancel before TTL expires - should revert
        skip(edgeTtl - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.RequestNotPastTtl.selector));
        kpkSharesContract.cancelRedemption(requestId);

        // Wait for TTL to expire exactly
        skip(1); // Now block.timestamp == request.timestamp + redemptionRequestTtl

        // At exactly TTL expiration, block.timestamp == request.timestamp + redemptionRequestTtl
        // The condition is block.timestamp < request.timestamp + redemptionRequestTtl
        // So it should NOT revert and cancellation should succeed
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testRedemptionRequestTtlWithZeroValue() public {
        // Test TTL validation with zero value
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.setRedemptionRequestTtl(0);
    }

    function testRedemptionRequestTtlWithVeryLargeValue() public {
        // Test TTL validation with very large value (should be capped at 7 days)
        uint64 largeTtl = 365 days; // 1 year
        uint64 expectedTtl = 7 days; // Contract caps at 7 days

        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(largeTtl);

        assertEq(kpkSharesContract.redemptionRequestTtl(), expectedTtl);

        // Create a redemption request
        uint256 requestId = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);

        // Wait for TTL to expire (7 days + 1)
        skip(expectedTtl + 1);

        // Should be able to cancel after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);

        // Check that request was cancelled
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    // ============================================================================
    // Request Processing Edge Cases Tests
    // ============================================================================

    function testProcessRedemptionRequestsWithComplexTtlScenarios() public {
        // Test complex TTL scenarios with multiple requests
        uint64 shortTtl = 1 hours;
        uint64 longTtl = 3 days;

        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(shortTtl);

        // Create multiple redemption requests
        uint256 requestId1 = _testRequestProcessing(false, alice, _sharesAmount(100), SHARES_PRICE, false);
        uint256 requestId2 = _testRequestProcessing(false, bob, _sharesAmount(200), SHARES_PRICE, false);

        // Wait for first TTL to expire
        skip(shortTtl + 1);

        // Cancel first request after TTL expires
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId1);

        // Change TTL to longer value
        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(longTtl);

        // Create another request with new TTL
        uint256 requestId3 = _testRequestProcessing(false, carol, _sharesAmount(300), SHARES_PRICE, false);

        // Wait for second TTL to expire
        skip(longTtl + 1);

        // Cancel second request after TTL expires
        vm.prank(bob);
        kpkSharesContract.cancelRedemption(requestId2);

        // Cancel third request after TTL expires
        vm.prank(carol);
        kpkSharesContract.cancelRedemption(requestId3);

        // Check that all requests were cancelled
        IkpkShares.UserRequest memory request1 = kpkSharesContract.getRequest(requestId1);
        IkpkShares.UserRequest memory request2 = kpkSharesContract.getRequest(requestId2);
        IkpkShares.UserRequest memory request3 = kpkSharesContract.getRequest(requestId3);
        assertEq(uint8(request1.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
        assertEq(uint8(request2.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
        assertEq(uint8(request3.requestStatus), uint8(IkpkShares.RequestStatus.CANCELLED));
    }

    function testRedemptionRequestProcessingEdgeCases() public {
        // Test redemption request processing edge cases to cover uncovered branches

        // First create some shares for users by processing deposit requests
        // Ensure users have sufficient USDC balance and allowance
        usdc.mint(alice, _usdcAmount(1000));
        usdc.mint(bob, _usdcAmount(1000));
        usdc.mint(carol, _usdcAmount(1000));
        usdc.mint(ops, _usdcAmount(1000));

        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        uint256 depositId1 = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        uint256 depositId2 = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            bob
        );
        vm.stopPrank();

        vm.startPrank(carol);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        uint256 depositId3 = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            carol
        );
        vm.stopPrank();

        vm.startPrank(ops);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        uint256 depositId4 = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            ops
        );
        vm.stopPrank();

        // Process all deposit requests to create shares
        uint256[] memory approveRequests = new uint256[](4);
        approveRequests[0] = depositId1;
        approveRequests[1] = depositId2;
        approveRequests[2] = depositId3;
        approveRequests[3] = depositId4;

        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now test with very small amounts
        uint256 requestId1 = _testRequestProcessing(false, alice, _sharesAmount(1), SHARES_PRICE, false);

        // Test with amounts that match the shares created from deposits
        // Use smaller amounts to ensure users have enough shares
        uint256 shares = _sharesAmount(1);
        // Use previewRedemption which accounts for redemption fees
        uint256 assets = kpkSharesContract.previewRedemption(shares, SHARES_PRICE, address(usdc));
        vm.startPrank(bob);
        kpkSharesContract.approve(address(kpkSharesContract), type(uint256).max);
        uint256 requestId2 = kpkSharesContract.requestRedemption(shares, assets, address(usdc), bob);
        vm.stopPrank();

        vm.startPrank(carol);
        kpkSharesContract.approve(address(kpkSharesContract), type(uint256).max);
        uint256 requestId3 = kpkSharesContract.requestRedemption(shares, assets / 2, address(usdc), carol);
        vm.stopPrank();

        vm.startPrank(ops);
        kpkSharesContract.approve(address(kpkSharesContract), type(uint256).max);
        uint256 requestId4 = kpkSharesContract.requestRedemption(shares, assets - 2, address(usdc), ops);
        vm.stopPrank();

        // Process all requests
        uint256[] memory approveRedemptionRequests = new uint256[](4);
        approveRedemptionRequests[0] = requestId1;
        approveRedemptionRequests[1] = requestId2;
        approveRedemptionRequests[2] = requestId3;
        approveRedemptionRequests[3] = requestId4;

        vm.prank(ops);
        kpkSharesContract.processRequests(approveRedemptionRequests, new uint256[](0), address(usdc), SHARES_PRICE);

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
    // Validation Function Tests (Coverage for lines 967-968)
    // ============================================================================

    function testValidateDepositRequestReturnTrue() public {
        // Test the _validateDepositRequest function to cover the return true path (lines 967-968)

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

        // Get the request to test validation
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(requestId);

        // The request should be valid (this tests the return true path in _validateDepositRequest)
        assertTrue(request.investor != address(0), "Investor should not be zero address");
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING), "Request should be pending");

        // Process the request to trigger _validateDepositRequest
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Check that the request was processed successfully (which means validation passed)
        IkpkShares.UserRequest memory processedRequest = kpkSharesContract.getRequest(requestId);
        assertEq(uint8(processedRequest.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
    }

    function testValidateRedemptionRequestReturnTrue() public {
        // Test the _validateRedemptionRequest function to cover validation logic

        // First create shares by processing a deposit request
        usdc.mint(alice, _usdcAmount(100));
        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), _usdcAmount(100));
        uint256 depositId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now create a redemption request
        vm.startPrank(alice);
        kpkSharesContract.approve(address(kpkSharesContract), type(uint256).max);
        // Use previewRedemption which accounts for redemption fees
        uint256 redeemId = kpkSharesContract.requestRedemption(
            _sharesAmount(1),
            kpkSharesContract.previewRedemption(_sharesAmount(1), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // Get the request to test validation
        IkpkShares.UserRequest memory request = kpkSharesContract.getRequest(redeemId);

        // The request should be valid
        assertTrue(request.investor != address(0), "Investor should not be zero address");
        assertEq(uint8(request.requestStatus), uint8(IkpkShares.RequestStatus.PENDING), "Request should be pending");

        // Process the redemption request to trigger _validateRedemptionRequest
        vm.prank(ops);
        uint256[] memory approveRedemptionRequests = new uint256[](1);
        approveRedemptionRequests[0] = redeemId;
        kpkSharesContract.processRequests(approveRedemptionRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Check that the request was processed successfully (which means validation passed)
        IkpkShares.UserRequest memory processedRequest = kpkSharesContract.getRequest(redeemId);
        assertEq(uint8(processedRequest.requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED));
    }
}
