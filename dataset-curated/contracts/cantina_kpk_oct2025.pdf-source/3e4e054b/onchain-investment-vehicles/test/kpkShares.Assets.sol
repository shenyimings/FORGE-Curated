// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Tests for kpkShares asset management functionality
contract kpkSharesAssetsTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Asset Update Tests
    // ============================================================================

    function testUpdateAsset() public {
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Check that asset was added to the list
        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 2); // USDC + new asset
        assertTrue(approvedAssets[0] == address(usdc) || approvedAssets[1] == address(usdc));
        assertTrue(approvedAssets[0] == address(newAsset) || approvedAssets[1] == address(newAsset));
    }

    function testUpdateAssetWithAlreadyApprovedAsset() public {
        // Try to approve an already approved asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), true, true, true);

        // Should not revert, but also not duplicate
        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 1); // Still only USDC
    }

    function testUpdateAssetUnauthorized() public {
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);
    }

    // ============================================================================
    // Asset Removal Tests
    // ============================================================================

    function testRemoveAsset() public {
        // Add a new asset (now properly configured on first call)
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Then remove it - this now properly clears oracle, canDeposit, canRedeem from mapping
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), false, false, false);

        IkpkShares.ApprovedAsset memory asset = kpkSharesContract.getApprovedAsset(address(newAsset));
        // Asset removal now properly clears the mapping data
        assertFalse(asset.canDeposit); // Cleared by removal logic
        assertFalse(asset.canRedeem); // Cleared by removal logic
        assertEq(asset.isFeeModuleAsset, false); // Cleared by removal logic
        assertEq(asset.asset, address(0)); // Asset address cleared
        assertEq(asset.decimals, 0); // Decimals cleared
    }

    function testRemoveAssetWithAssetNotInList() public {
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        // Try to remove an asset that was never approved - this should revert with InvalidArguments
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(newAsset), true, false, false);
    }

    function testRemoveAssetUnauthorized() public {
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.NotAuthorized.selector));
        kpkSharesContract.updateAsset(address(newAsset), true, false, false);
    }

    function testCannotRemoveLastAsset() public {
        // USDC is the only asset
        // Try to remove it completely - should revert
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(usdc), false, false, false);

        // Add another asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Now we can remove USDC completely
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), false, false, false);

        // Verify USDC is removed
        IkpkShares.ApprovedAsset memory usdcAsset = kpkSharesContract.getApprovedAsset(address(usdc));
        assertEq(usdcAsset.asset, address(0));

        // Verify newAsset is still there
        IkpkShares.ApprovedAsset memory newAssetConfig = kpkSharesContract.getApprovedAsset(address(newAsset));
        assertEq(newAssetConfig.asset, address(newAsset));

        // Now try to remove newAsset (which is now the last asset) - should revert
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(newAsset), false, false, false);
    }

    // ============================================================================
    // Asset Validation Tests
    // ============================================================================

    function testIsAsset() public {
        // USDC was properly configured during setup with updateAsset
        IkpkShares.ApprovedAsset memory asset = kpkSharesContract.getApprovedAsset(address(usdc));
        assertTrue(asset.canDeposit); // Set to true during setup
        assertTrue(asset.canRedeem); // Set to true during setup
        assertEq(asset.decimals, 6);
        assertEq(asset.asset, address(usdc));
        assertEq(asset.isFeeModuleAsset, true);
        // Non-existent asset should return default values
        assertFalse(kpkSharesContract.getApprovedAsset(address(alice)).canDeposit);

        // Test with a new asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        assertFalse(kpkSharesContract.getApprovedAsset(address(newAsset)).canDeposit);

        // Add it (now properly sets all fields on first call)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);
        assertTrue(kpkSharesContract.getApprovedAsset(address(newAsset)).canDeposit);
    }

    function testAssetDecimals() public {
        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();

        assertEq(kpkSharesContract.getApprovedAsset(address(usdc)).decimals, 6);

        // Test with a new asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 12);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        assertEq(kpkSharesContract.getApprovedAsset(address(newAsset)).decimals, 12);

        approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 2);
        assertEq(approvedAssets[0], address(usdc));
        assertEq(approvedAssets[1], address(newAsset));
    }

    function testGetApprovedAssets() public {
        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 1);
        assertEq(approvedAssets[0], address(usdc));

        // Add another asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 2);

        // Check that both assets are in the list
        bool hasUsdc = false;
        bool hasNewAsset = false;
        for (uint256 i = 0; i < approvedAssets.length; i++) {
            if (approvedAssets[i] == address(usdc)) hasUsdc = true;
            if (approvedAssets[i] == address(newAsset)) hasNewAsset = true;
        }
        assertTrue(hasUsdc);
        assertTrue(hasNewAsset);
    }

    // ============================================================================
    // Asset Integration Tests
    // ============================================================================

    function testMultipleAssets() public {
        // Add multiple assets
        Mock_ERC20 asset1 = new Mock_ERC20("ASSET_1", 8);
        Mock_ERC20 asset2 = new Mock_ERC20("ASSET_2", 12);
        Mock_ERC20 asset3 = new Mock_ERC20("ASSET_3", 18);

        vm.startPrank(ops);
        kpkSharesContract.updateAsset(address(asset1), true, true, true);
        kpkSharesContract.updateAsset(address(asset2), true, true, true);
        kpkSharesContract.updateAsset(address(asset3), true, true, true);
        vm.stopPrank();

        // Check that all assets are approved
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset1)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset2)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset3)).canDeposit);

        // Check the list
        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 4); // USDC + 3 new assets
    }

    function testAssetRemovalWithComplexState() public {
        // Use the existing USDC asset which is already configured and the safe holds
        // We can't remove USDC completely since it's the base asset, but we can test
        // the logic by temporarily disabling it and then re-enabling it

        // First, ensure USDC is enabled for both deposit and redeem
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), true, true, true);

        // Create a subscription request using USDC (which the safe already holds)
        vm.startPrank(alice);
        usdc.approve(address(kpkSharesContract), type(uint256).max);
        uint256 requestId = kpkSharesContract.requestSubscription(
            _usdcAmount(100),
            kpkSharesContract.assetsToShares(_usdcAmount(100), SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        // Process the subscription request
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Now should be able to disable USDC subscriptions since no pending requests
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), true, false, true);
        assertFalse(kpkSharesContract.getApprovedAsset(address(usdc)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(usdc)).canRedeem);

        // Re-enable USDC subscriptions
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), true, true, true);
        assertTrue(kpkSharesContract.getApprovedAsset(address(usdc)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(usdc)).canRedeem);
    }

    // ============================================================================
    // Asset Management Edge Cases Tests
    // ============================================================================

    function testAssetUpdateWithInvalidConfiguration() public {
        // Test asset update with invalid configuration (both canDeposit and canRedeem false)
        Mock_ERC20 asset = new Mock_ERC20("ASSET", 18);

        // Try to add asset with both flags false - should revert
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(asset), true, false, false);
    }

    function testAssetUpdateWithZeroAddressValidation() public {
        // Test asset update with zero address validation
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(0), true, true, true);
    }

    function testAssetUpdateWithComplexStateTransitions() public {
        // Test complex asset state transitions
        Mock_ERC20 asset = new Mock_ERC20("ASSET", 18);

        // Add asset with both flags true
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canRedeem);

        // Update to deposit only
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, false);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);
        assertFalse(kpkSharesContract.getApprovedAsset(address(asset)).canRedeem);

        // Update to redeem only
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, false, true);
        assertFalse(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canRedeem);

        // Update back to both
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canRedeem);
    }

    function testAssetRemovalAndReapproval() public {
        // Test asset removal and reapproval
        Mock_ERC20 asset = new Mock_ERC20("ASSET", 18);

        // Add asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);

        // Remove asset (this now properly clears mapping data)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, false, false);
        assertFalse(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit); // Cleared by removal

        // Re-add asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);
    }

    function testAssetUpdateWithExistingAsset() public {
        // Test updating an existing asset
        Mock_ERC20 asset = new Mock_ERC20("ASSET", 18);

        // Add asset initially
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);

        // Update the same asset with different configuration
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, false, true);

        // Check that the asset was updated
        IkpkShares.ApprovedAsset memory assetConfig = kpkSharesContract.getApprovedAsset(address(asset));
        assertFalse(assetConfig.canDeposit);
        assertTrue(assetConfig.canRedeem);
    }

    function testAssetUpdateWithNewIsUsd() public {
        // Test updating an asset with a new isFeeModuleAsset value
        Mock_ERC20 asset = new Mock_ERC20("ASSET", 18);

        // Add asset initially
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);

        // Update with new isFeeModuleAsset value
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), false, true, true);

        // Check that the isFeeModuleAsset was updated
        IkpkShares.ApprovedAsset memory assetConfig = kpkSharesContract.getApprovedAsset(address(asset));
        assertEq(assetConfig.isFeeModuleAsset, false);
    }

    function testAssetUpdateWithSymbolAndDecimals() public {
        // Test that asset symbol and decimals are properly set
        Mock_ERC20 asset = new Mock_ERC20("TEST_ASSET", 6);

        // Add asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);

        // Check that symbol and decimals were set
        IkpkShares.ApprovedAsset memory assetConfig = kpkSharesContract.getApprovedAsset(address(asset));
        assertEq(assetConfig.symbol, "TEST_ASSET");
        assertEq(assetConfig.decimals, 6);
    }

    // ============================================================================
    // Asset Removal Edge Cases
    // ============================================================================

    function testRemoveAssetWithPendingSubscriptions() public {
        // Create a subscription request (not processed)
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Verify there's a pending request and subscriptionAssets > 0
        assertGt(kpkSharesContract.subscriptionAssets(address(usdc)), 0);

        // Try to remove asset with pending subscriptions
        // Should revert with InvalidArguments (cannot remove with subscriptionAssets > 0)
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(usdc), false, false, false);
    }

    function testRemoveAssetWithPendingRedemptions() public {
        // First create shares by processing a subscription
        uint256 depositId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Create a redemption request (not processed)
        uint256 redeemId = _testRequestProcessing(false, alice, _sharesAmount(50), SHARES_PRICE, false);

        // Verify subscriptionAssets is 0 (request was processed)
        assertEq(kpkSharesContract.subscriptionAssets(address(usdc)), 0);

        // Try to remove asset with pending redemptions
        // Should revert with InvalidArguments (cannot remove with _pendingRequestsCount > 0)
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(usdc), false, false, false);
    }

    function testRemoveAssetWithSubscriptionAssetsAfterProcessing() public {
        // Create and process a subscription to have subscriptionAssets > 0 initially
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Verify subscriptionAssets > 0 before processing
        assertGt(kpkSharesContract.subscriptionAssets(address(usdc)), 0);

        // Process the request
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify subscriptionAssets is now 0 (request was processed)
        assertEq(kpkSharesContract.subscriptionAssets(address(usdc)), 0);

        // Now should be able to remove asset (no pending requests, subscriptionAssets == 0)
        // But first need to add another asset since we can't remove the last one
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Now can remove USDC
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), false, false, false);

        // Verify USDC is removed
        IkpkShares.ApprovedAsset memory usdcAsset = kpkSharesContract.getApprovedAsset(address(usdc));
        assertEq(usdcAsset.asset, address(0));
    }

    function testRemoveLastAsset() public {
        // Add a second asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Remove the new asset (not the last one)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), false, false, false);

        // Verify newAsset is removed
        IkpkShares.ApprovedAsset memory newAssetConfig = kpkSharesContract.getApprovedAsset(address(newAsset));
        assertEq(newAssetConfig.asset, address(0));

        // Now try to remove USDC (the last asset)
        // Should revert with InvalidArguments (cannot remove last asset)
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(usdc), false, false, false);
    }

    function testRemoveAssetWithPendingSubscriptionAndRedemption() public {
        // Create a subscription request (not processed)
        uint256 subscriptionId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Create shares for redemption
        uint256 depositId = _testRequestProcessing(true, bob, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Create a redemption request (not processed)
        uint256 redeemId = _testRequestProcessing(false, bob, _sharesAmount(50), SHARES_PRICE, false);

        // Verify subscriptionAssets > 0 (from pending subscription)
        assertGt(kpkSharesContract.subscriptionAssets(address(usdc)), 0);

        // Try to remove asset with both pending subscription and redemption
        // Should revert with InvalidArguments (subscriptionAssets > 0 check happens first)
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(usdc), false, false, false);
    }

    // ============================================================================
    // Internal Helper Function Tests
    // ============================================================================

    function testShadowAssetDuringRemoval() public {
        // Add a new asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Verify asset is in the list
        address[] memory approvedAssetsBefore = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssetsBefore.length, 2); // USDC + newAsset
        bool hasNewAsset = false;
        for (uint256 i = 0; i < approvedAssetsBefore.length; i++) {
            if (approvedAssetsBefore[i] == address(newAsset)) {
                hasNewAsset = true;
                break;
            }
        }
        assertTrue(hasNewAsset);

        // Create and process a subscription to ensure no pending requests
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Add another asset so we can remove newAsset (can't remove last asset)
        Mock_ERC20 anotherAsset = new Mock_ERC20("ANOTHER", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(anotherAsset), true, true, true);

        // Remove newAsset - this should call _shadowAsset internally
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), false, false, false);

        // Verify asset is no longer in approved list (shadowed)
        address[] memory approvedAssetsAfter = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssetsAfter.length, 2); // USDC + anotherAsset (newAsset removed)
        bool stillHasNewAsset = false;
        for (uint256 i = 0; i < approvedAssetsAfter.length; i++) {
            if (approvedAssetsAfter[i] == address(newAsset)) {
                stillHasNewAsset = true;
                break;
            }
        }
        assertFalse(stillHasNewAsset, "Asset should be removed from approved list");

        // Verify asset mapping is cleared
        IkpkShares.ApprovedAsset memory assetConfig = kpkSharesContract.getApprovedAsset(address(newAsset));
        assertEq(assetConfig.asset, address(0));
    }

    function testHasPendingRequestsReturnsTrue() public {
        // Create a subscription request (not processed)
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        // Try to remove asset - should check _hasPendingRequests internally and revert
        // This tests _hasPendingRequests returning true
        vm.prank(ops);
        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        kpkSharesContract.updateAsset(address(usdc), false, false, false);
    }

    function testHasPendingRequestsReturnsFalse() public {
        // Process all requests first
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Verify subscriptionAssets is 0 and no pending requests
        assertEq(kpkSharesContract.subscriptionAssets(address(usdc)), 0);

        // Add another asset so we can remove USDC (can't remove last asset)
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Now try to remove asset - should succeed (no pending requests)
        // This tests _hasPendingRequests returning false
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(usdc), false, false, false);

        // Verify USDC is removed
        IkpkShares.ApprovedAsset memory usdcAsset = kpkSharesContract.getApprovedAsset(address(usdc));
        assertEq(usdcAsset.asset, address(0));
    }

    // ============================================================================
    // Pending Subscription Requests Tests
    // ============================================================================

    // ============================================================================
    // Asset Event Tests
    // ============================================================================

    function testAssetEventsEmitted() public {
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        // Test asset added event (when adding a new asset)
        // Now emits both AssetAdd and AssetUpdated events
        vm.prank(ops);
        vm.expectEmit(true, true, false, true);
        emit IkpkShares.AssetAdd(address(newAsset));
        vm.expectEmit(true, true, false, true);
        emit IkpkShares.AssetUpdate(address(newAsset), true, true, true);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Test asset updated event (when updating existing asset)
        vm.prank(ops);
        vm.expectEmit(true, true, false, true);
        emit IkpkShares.AssetUpdate(address(newAsset), true, false, true);
        kpkSharesContract.updateAsset(address(newAsset), true, false, true);

        // Test asset removed event (when setting both canDeposit and canRedeem to false)
        vm.prank(ops);
        vm.expectEmit(true, true, false, true);
        emit IkpkShares.AssetRemove(address(newAsset));
        kpkSharesContract.updateAsset(address(newAsset), true, false, false);
    }

    function testAssetUpdatedEvent() public {
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);

        // First add the asset (now properly emits both AssetAdded and AssetUpdated)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Test AssetUpdated event when changing isFeeModuleAsset
        vm.prank(ops);
        vm.expectEmit(true, true, false, true);
        emit IkpkShares.AssetUpdate(address(newAsset), false, true, true);
        kpkSharesContract.updateAsset(address(newAsset), false, true, true);

        // Test AssetUpdated event when changing canDeposit only
        vm.prank(ops);
        vm.expectEmit(true, true, false, true);
        emit IkpkShares.AssetUpdate(address(newAsset), false, false, true);
        kpkSharesContract.updateAsset(address(newAsset), false, false, true);
    }

    // ============================================================================
    // Edge Cases and Error Handling
    // ============================================================================

    // ============================================================================
    // Asset State Persistence Tests
    // ============================================================================

    function testAssetStatePersistence() public {
        Mock_ERC20 asset = new Mock_ERC20("ASSET", 18);

        // Add asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, true, true);

        // Check state
        assertTrue(kpkSharesContract.getApprovedAsset(address(asset)).canDeposit);
        assertEq(kpkSharesContract.getApprovedAsset(address(asset)).decimals, 18);

        // Remove asset
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset), true, false, false);

        // Check state after removal - mapping data is now properly cleared
        IkpkShares.ApprovedAsset memory removedAsset = kpkSharesContract.getApprovedAsset(address(asset));
        assertFalse(removedAsset.canDeposit); // Cleared by removal logic
        assertFalse(removedAsset.canRedeem); // Cleared by removal logic
        assertEq(removedAsset.decimals, 0); // Decimals cleared
        assertEq(removedAsset.isFeeModuleAsset, false); // isFeeModuleAsset cleared
        assertEq(removedAsset.asset, address(0)); // Asset address cleared

        // Check that it's not in the list
        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 1); // Only USDC
        assertEq(approvedAssets[0], address(usdc));
    }

    function testShadowAssetRemovesFromDifferentPositions() public {
        // Add multiple assets to test removal from different positions
        Mock_ERC20 asset1 = new Mock_ERC20("ASSET1", 18);
        Mock_ERC20 asset2 = new Mock_ERC20("ASSET2", 18);
        Mock_ERC20 asset3 = new Mock_ERC20("ASSET3", 18);

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset1), true, true, true);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset2), true, true, true);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset3), true, true, true);

        // Verify all assets are in the list
        address[] memory assetsBefore = kpkSharesContract.getApprovedAssets();
        assertEq(assetsBefore.length, 4); // USDC + 3 new assets

        // Process a request to ensure no pending requests
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Test 1: Remove middle asset (asset2) - tests loop finding asset at position != 0 and != last
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset2), false, false, false);

        address[] memory assetsAfter1 = kpkSharesContract.getApprovedAssets();
        assertEq(assetsAfter1.length, 3); // USDC + asset1 + asset3
        bool hasAsset2 = false;
        for (uint256 i = 0; i < assetsAfter1.length; i++) {
            if (assetsAfter1[i] == address(asset2)) {
                hasAsset2 = true;
                break;
            }
        }
        assertFalse(hasAsset2, "Asset2 should be removed");

        // Test 2: Remove first new asset (asset1) - tests loop finding asset at position != last
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset1), false, false, false);

        address[] memory assetsAfter2 = kpkSharesContract.getApprovedAssets();
        assertEq(assetsAfter2.length, 2); // USDC + asset3
        bool hasAsset1 = false;
        for (uint256 i = 0; i < assetsAfter2.length; i++) {
            if (assetsAfter2[i] == address(asset1)) {
                hasAsset1 = true;
                break;
            }
        }
        assertFalse(hasAsset1, "Asset1 should be removed");

        // Test 3: Remove last asset (asset3) - tests loop finding asset at last position
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset3), false, false, false);

        address[] memory assetsAfter3 = kpkSharesContract.getApprovedAssets();
        assertEq(assetsAfter3.length, 1); // Only USDC
        bool hasAsset3 = false;
        for (uint256 i = 0; i < assetsAfter3.length; i++) {
            if (assetsAfter3[i] == address(asset3)) {
                hasAsset3 = true;
                break;
            }
        }
        assertFalse(hasAsset3, "Asset3 should be removed");
        assertEq(assetsAfter3[0], address(usdc), "USDC should remain");
    }

    function testShadowAssetRemovesMultipleAssetsInSequence() public {
        // Add multiple assets
        Mock_ERC20 asset1 = new Mock_ERC20("ASSET1", 18);
        Mock_ERC20 asset2 = new Mock_ERC20("ASSET2", 18);
        Mock_ERC20 asset3 = new Mock_ERC20("ASSET3", 18);
        Mock_ERC20 asset4 = new Mock_ERC20("ASSET4", 18);

        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset1), true, true, true);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset2), true, true, true);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset3), true, true, true);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset4), true, true, true);

        // Process a request to ensure no pending requests
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Remove assets in sequence to test array manipulation
        // This tests the swap-and-pop pattern multiple times

        // Remove asset2 (middle)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset2), false, false, false);
        address[] memory assets1 = kpkSharesContract.getApprovedAssets();
        assertEq(assets1.length, 4); // USDC + asset1 + asset3 + asset4

        // Remove asset4 (last)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset4), false, false, false);
        address[] memory assets2 = kpkSharesContract.getApprovedAssets();
        assertEq(assets2.length, 3); // USDC + asset1 + asset3

        // Remove asset1 (first new asset)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset1), false, false, false);
        address[] memory assets3 = kpkSharesContract.getApprovedAssets();
        assertEq(assets3.length, 2); // USDC + asset3

        // Remove asset3 (last remaining new asset)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(asset3), false, false, false);
        address[] memory assets4 = kpkSharesContract.getApprovedAssets();
        assertEq(assets4.length, 1); // Only USDC
        assertEq(assets4[0], address(usdc));

        // Verify all assets are removed from the list
        for (uint256 i = 0; i < assets4.length; i++) {
            assertTrue(assets4[i] == address(usdc), "Only USDC should remain");
        }
    }

    function testShadowAssetArrayManipulation() public {
        // This test specifically focuses on the array manipulation in _shadowAsset
        // Add 5 assets to have a substantial array
        Mock_ERC20[] memory assets = new Mock_ERC20[](5);
        for (uint256 i = 0; i < 5; i++) {
            assets[i] = new Mock_ERC20(string(abi.encodePacked("ASSET", i)), 18);
            vm.prank(ops);
            kpkSharesContract.updateAsset(address(assets[i]), true, true, true);
        }

        // Process a request to ensure no pending requests
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        kpkSharesContract.processRequests(approveRequests, new uint256[](0), address(usdc), SHARES_PRICE);

        // Get initial list
        address[] memory initialAssets = kpkSharesContract.getApprovedAssets();
        assertEq(initialAssets.length, 6); // USDC + 5 new assets

        // Remove asset at index 2 (middle of new assets)
        // This tests the loop finding the asset and swapping with last element
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(assets[2]), false, false, false);

        address[] memory afterRemoval = kpkSharesContract.getApprovedAssets();
        assertEq(afterRemoval.length, 5); // USDC + 4 remaining assets

        // Verify asset[2] is not in the list
        bool found = false;
        for (uint256 i = 0; i < afterRemoval.length; i++) {
            if (afterRemoval[i] == address(assets[2])) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Asset[2] should be removed");

        // Verify other assets are still present
        bool hasUsdc = false;
        bool hasAsset0 = false;
        bool hasAsset1 = false;
        bool hasAsset3 = false;
        bool hasAsset4 = false;

        for (uint256 i = 0; i < afterRemoval.length; i++) {
            if (afterRemoval[i] == address(usdc)) hasUsdc = true;
            if (afterRemoval[i] == address(assets[0])) hasAsset0 = true;
            if (afterRemoval[i] == address(assets[1])) hasAsset1 = true;
            if (afterRemoval[i] == address(assets[3])) hasAsset3 = true;
            if (afterRemoval[i] == address(assets[4])) hasAsset4 = true;
        }

        assertTrue(hasUsdc, "USDC should remain");
        assertTrue(hasAsset0, "Asset0 should remain");
        assertTrue(hasAsset1, "Asset1 should remain");
        assertTrue(hasAsset3, "Asset3 should remain");
        assertTrue(hasAsset4, "Asset4 should remain");
    }

    function testAssetListOrdering() public {
        // Add multiple assets to test ordering
        Mock_ERC20 asset1 = new Mock_ERC20("ASSET1", 18);
        Mock_ERC20 asset2 = new Mock_ERC20("ASSET2", 18);
        Mock_ERC20 asset3 = new Mock_ERC20("ASSET3", 18);

        vm.startPrank(ops);
        kpkSharesContract.updateAsset(address(asset1), true, true, true);
        kpkSharesContract.updateAsset(address(asset2), true, true, true);
        kpkSharesContract.updateAsset(address(asset3), true, true, true);
        vm.stopPrank();

        address[] memory approvedAssets = kpkSharesContract.getApprovedAssets();
        assertEq(approvedAssets.length, 4); // USDC + 3 new assets

        // Check that assets are added in order
        assertEq(approvedAssets[0], address(usdc));
        assertEq(approvedAssets[1], address(asset1));
        assertEq(approvedAssets[2], address(asset2));
        assertEq(approvedAssets[3], address(asset3));
    }

    // ============================================================================
    // Pending Subscription Requests Tests
    // ============================================================================

    function testUpdateAssetCanSetCanDepositToFalseWithoutPendingDeposits() public {
        // First add a new asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // No subscription requests made, so subscriptionAssets should be 0
        assertEq(kpkSharesContract.subscriptionAssets(address(newAsset)), 0);

        // Should be able to set canDeposit to false without pending subscriptions
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, false, true);

        // Verify the asset no longer allows subscriptions
        assertFalse(kpkSharesContract.getApprovedAsset(address(newAsset)).canDeposit);
        assertTrue(kpkSharesContract.getApprovedAsset(address(newAsset)).canRedeem);
    }

    function testUpdateAssetCanSetCanDepositToFalseAfterProcessingSubscriptions() public {
        // First add a new asset
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Mint tokens to alice and approve the contract
        newAsset.mint(alice, 1000e18);
        vm.startPrank(alice);
        newAsset.approve(address(kpkSharesContract), type(uint256).max);

        // Create a subscription request
        uint256 requestId = kpkSharesContract.requestSubscription(
            100e18,
            1e18, // 1 USD per share
            address(newAsset),
            alice
        );
        vm.stopPrank();

        // Process the subscription request
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(newAsset), SHARES_PRICE);

        // Verify the subscription assets have been processed (should be 0 now)
        assertEq(kpkSharesContract.subscriptionAssets(address(newAsset)), 0);

        // Now should be able to set canDeposit to false since no pending subscriptions
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, false, true);

        // Verify the asset no longer allows subscriptions
        assertFalse(kpkSharesContract.getApprovedAsset(address(newAsset)).canDeposit);
    }

    function testUpdateAssetCanSetCanDepositToTrueRegardlessOfPendingSubscriptions() public {
        // First add a new asset with canDeposit = false
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.startPrank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, false, true);
        vm.stopPrank();

        // Should be able to set canDeposit to true even with pending subscriptions (if any existed)
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Verify the asset now allows subscriptions
        assertTrue(kpkSharesContract.getApprovedAsset(address(newAsset)).canDeposit);
    }
}
