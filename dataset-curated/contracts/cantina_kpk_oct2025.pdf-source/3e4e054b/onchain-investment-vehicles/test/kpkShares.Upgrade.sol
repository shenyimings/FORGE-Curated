// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice Tests for kpkShares upgrade functionality and UUPS proxy
contract kpkSharesUpgradeTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Basic Upgrade Tests
    // ============================================================================

    function testUpgradeImplementation() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify the upgrade worked
        assertEq(kpkSharesContract.name(), "kpk");
        assertEq(kpkSharesContract.symbol(), "kpk");
        assertTrue(kpkSharesContract.isApprovedAsset(address(usdc)));
    }

    function testUpgradeImplementationAndCall() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy with a call
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(
            newImplementation, abi.encodeWithSignature("setManagementFeeRate(uint256)", 200)
        );

        // Verify the upgrade worked and the call was executed
        assertEq(kpkSharesContract.managementFeeRate(), 200);
    }

    function testUpgradeUnauthorized() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Try to upgrade without admin role
        vm.prank(alice);
        vm.expectRevert(); // Should revert due to insufficient permissions
        kpkSharesContract.upgradeToAndCall(newImplementation, "");
    }

    // ============================================================================
    // Upgrade State Preservation Tests
    // ============================================================================

    function testUpgradePreservesState() public {
        // Set some state before upgrade
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(150);
        vm.prank(admin);
        kpkSharesContract.setRedemptionFeeRate(75);
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(2 days);

        // Create some shares
        _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, true);

        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify state is preserved
        assertEq(kpkSharesContract.managementFeeRate(), 150);
        assertEq(kpkSharesContract.redemptionFeeRate(), 75);
        assertEq(kpkSharesContract.subscriptionRequestTtl(), 2 days);
        assertGt(kpkSharesContract.balanceOf(alice), 0);
        assertTrue(kpkSharesContract.isApprovedAsset(address(usdc)));
    }

    function testUpgradePreservesRoles() public {
        // Grant additional roles before upgrade
        vm.prank(admin);
        kpkSharesContract.grantRole(OPERATOR, bob);

        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify roles are preserved
        assertTrue(kpkSharesContract.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(kpkSharesContract.hasRole(OPERATOR, ops));
        assertTrue(kpkSharesContract.hasRole(OPERATOR, bob));
    }

    function testUpgradePreservesApprovedAssets() public {
        // Add new asset before upgrade
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);

        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify approved assets are preserved
        assertTrue(kpkSharesContract.isApprovedAsset(address(usdc)));
        assertTrue(kpkSharesContract.isApprovedAsset(address(newAsset)));
        assertEq(kpkSharesContract.assetDecimals(address(newAsset)), 18);
    }

    // ============================================================================
    // Upgrade Functionality Tests
    // ============================================================================

    function testUpgradeWithNewFunctionality() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Test that existing functionality still works
        uint256 requestId = _testRequestProcessing(true, bob, _usdcAmount(200), SHARES_PRICE, false);

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        assertGt(kpkSharesContract.balanceOf(bob), 0);
    }

    function testUpgradeWithStateChanges() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Test that state changes still work
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(300);
        assertEq(kpkSharesContract.managementFeeRate(), 300);

        vm.prank(admin);
        kpkSharesContract.setRedemptionFeeRate(100);
        assertEq(kpkSharesContract.redemptionFeeRate(), 100);
    }

    // ============================================================================
    // Upgrade Error Handling Tests
    // ============================================================================

    function testUpgradeToInvalidImplementation() public {
        // Try to upgrade to an invalid address
        vm.prank(admin);
        vm.expectRevert(); // Should revert when upgrading to invalid implementation
        kpkSharesContract.upgradeToAndCall(address(0), "");
    }

    function testUpgradeWithInvalidCallData() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Try to upgrade with invalid call data
        vm.prank(admin);
        vm.expectRevert(); // Should revert with invalid call data
        kpkSharesContract.upgradeToAndCall(newImplementation, abi.encodeWithSignature("nonexistentFunction()"));
    }

    // ============================================================================
    // Upgrade Integration Tests
    // ============================================================================

    function testUpgradeWithActiveRequests() public {
        // Create active requests before upgrade
        uint256 depositRequestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        uint256 redeemRequestId = _testRequestProcessing(false, bob, _sharesAmount(50), SHARES_PRICE, false);

        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify requests are still accessible
        IkpkShares.UserRequest memory depositRequest = kpkSharesContract.getRequest(depositRequestId);
        IkpkShares.UserRequest memory redeemRequest = kpkSharesContract.getRequest(redeemRequestId);

        assertEq(uint8(depositRequest.requestStatus), uint8(IkpkShares.RequestStatus.PENDING));
        assertEq(uint8(redeemRequest.requestStatus), uint8(IkpkShares.RequestStatus.PENDING));

        // Process requests after upgrade
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = depositRequestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        vm.prank(ops);
        uint256[] memory redeemApproveRequests = new uint256[](1);
        redeemApproveRequests[0] = redeemRequestId;
        uint256[] memory redeemRejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(redeemApproveRequests, redeemRejectRequests, address(usdc), SHARES_PRICE);

        // Verify processing worked
        assertEq(
            uint8(kpkSharesContract.getRequest(depositRequestId).requestStatus),
            uint8(IkpkShares.RequestStatus.PROCESSED)
        );
        assertEq(
            uint8(kpkSharesContract.getRequest(redeemRequestId).requestStatus),
            uint8(IkpkShares.RequestStatus.PROCESSED)
        );
    }

    function testUpgradeWithFees() public {
        // Enable fees before upgrade
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(100);
        vm.prank(admin);
        kpkSharesContract.setRedemptionFeeRate(50);

        // Create shares for testing
        uint256 shares = _sharesAmount(1000);
        _createSharesForTesting(alice, shares);

        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Test fee charging after upgrade
        uint256 timeElapsed = 365 days;
        skip(timeElapsed);

        uint256 initialFeeBalance = kpkSharesContract.balanceOf(feeRecipient);

        // Create and process redeem request to trigger fee charging
        vm.startPrank(alice);
        // Use previewRedemption which accounts for redemption fees
        uint256 requestId = kpkSharesContract.requestRedemption(
            shares / 4,
            kpkSharesContract.previewRedemption(shares / 4, SHARES_PRICE, address(usdc)),
            address(usdc),
            alice
        );
        vm.stopPrank();

        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        uint256 finalFeeBalance = kpkSharesContract.balanceOf(feeRecipient);
        assertGt(finalFeeBalance, initialFeeBalance);
    }

    // ============================================================================
    // Multiple Upgrade Tests
    // ============================================================================

    function testMultipleUpgrades() public {
        // First upgrade
        address implementation1 = address(new KpkShares());
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(implementation1, "");

        // Set some state
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(200);

        // Second upgrade
        address implementation2 = address(new KpkShares());
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(implementation2, "");

        // Verify state is preserved
        assertEq(kpkSharesContract.managementFeeRate(), 200);

        // Third upgrade
        address implementation3 = address(new KpkShares());
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(implementation3, "");

        // Verify state is still preserved
        assertEq(kpkSharesContract.managementFeeRate(), 200);
    }

    function testUpgradeRollback() public {
        // Set initial state
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(100);

        // First upgrade
        address implementation1 = address(new KpkShares());
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(implementation1, "");

        // Change state
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(300);

        // Rollback to original implementation
        address originalImplementation = address(new KpkShares());
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(originalImplementation, "");

        // Verify state is preserved (not rolled back)
        assertEq(kpkSharesContract.managementFeeRate(), 300);
    }

    // ============================================================================
    // Upgrade Security Tests
    // ============================================================================

    function testUpgradeAuthorization() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Try to upgrade with different accounts
        vm.prank(alice);
        vm.expectRevert(); // Should revert
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        vm.prank(bob);
        vm.expectRevert(); // Should revert
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        vm.prank(ops);
        vm.expectRevert(); // Should revert
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Only admin should be able to upgrade
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeWithRoleChanges() public {
        // Grant additional roles before upgrade
        vm.prank(admin);
        kpkSharesContract.grantRole(OPERATOR, carol);

        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Upgrade the proxy
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify roles are preserved and functional
        assertTrue(kpkSharesContract.hasRole(OPERATOR, carol));

        // Test that carol can use operator functions
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);

        vm.prank(carol);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        assertEq(
            uint8(kpkSharesContract.getRequest(requestId).requestStatus), uint8(IkpkShares.RequestStatus.PROCESSED)
        );
    }

    // ============================================================================
    // Upgrade Event Tests
    // ============================================================================

    function testUpgradeEvents() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Test upgrade event
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IERC1967.Upgraded(newImplementation);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");
    }

    function testUpgradeAndCallEvents() public {
        // Deploy new implementation
        address newImplementation = address(new KpkShares());

        // Test upgrade and call event
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IERC1967.Upgraded(newImplementation);
        kpkSharesContract.upgradeToAndCall(
            newImplementation, abi.encodeWithSignature("setManagementFeeRate(uint256)", 250)
        );

        // Verify the call was executed
        assertEq(kpkSharesContract.managementFeeRate(), 250);
    }
}
