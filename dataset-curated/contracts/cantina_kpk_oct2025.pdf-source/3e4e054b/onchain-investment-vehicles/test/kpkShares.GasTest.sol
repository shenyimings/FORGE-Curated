// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";
import {console} from "forge-std/console.sol";

/// @notice Gas cost measurement tests for kpkShares contract
contract kpkSharesGasTest is kpkSharesTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============================================================================
    // Gas Measurement Tests
    // ============================================================================

    function testGas_RequestSubscription() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        uint256 gasStart = gasleft();
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for requestSubscription:", gasUsed);
        assertTrue(gasUsed > 0);
        assertEq(requestId, 1);
    }

    function testGas_RequestRedemption() public {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        // First create shares for testing
        uint256 requestIdSubscription = _createSharesForTesting(alice, shares);
        assertEq(requestIdSubscription, 1);

        // Use previewRedemption which accounts for redemption fees
        uint256 assetsOut = kpkSharesContract.previewRedemption(shares, price, address(usdc));
        uint256 gasStart = gasleft();
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for requestRedemption:", gasUsed);
        assertTrue(gasUsed > 0);
        assertEq(requestId, 2);
    }

    function testGas_CancelSubscription() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        // Create subscription request
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);

        // Fast forward past TTL
        vm.warp(block.timestamp + SUBSCRIPTION_REQUEST_TTL + 1);

        uint256 gasStart = gasleft();
        vm.prank(alice);
        kpkSharesContract.cancelSubscription(requestId);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for cancelSubscription:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_CancelRedemption() public {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        // Create shares and redemption request
        _createSharesForTesting(alice, shares);
        uint256 assetsOut = kpkSharesContract.previewRedemption(shares, price, address(usdc));
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);

        // Fast forward past TTL
        vm.warp(block.timestamp + REDEMPTION_REQUEST_TTL + 1);

        uint256 gasStart = gasleft();
        vm.prank(alice);
        kpkSharesContract.cancelRedemption(requestId);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for cancelRedemption:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_ProcessSubscriptionRequests_Approve() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        // Create subscription request
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);

        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (approve):", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_ProcessSubscriptionRequests_Reject() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        // Create subscription request
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);

        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (reject):", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_ProcessRedemptionRequests_Approve() public {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        // Create shares and redemption request
        uint256 requestIdSubscription = _createSharesForTesting(alice, shares);
        assertEq(requestIdSubscription, 1);
        // Use previewRedemption which accounts for redemption fees
        uint256 assetsOut = kpkSharesContract.previewRedemption(shares, price, address(usdc));
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);

        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (approve):", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_ProcessRedemptionRequests_Reject() public {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        // Create shares and redemption request
        uint256 requestIdSubscription = _createSharesForTesting(alice, shares);
        assertEq(requestIdSubscription, 1);
        // Use previewRedemption which accounts for redemption fees
        uint256 assetsOut = kpkSharesContract.previewRedemption(shares, price, address(usdc));
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);

        uint256[] memory approveRequests = new uint256[](0);
        uint256[] memory rejectRequests = new uint256[](1);
        rejectRequests[0] = requestId;

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (reject):", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_UpdateAsset() public {
        Mock_ERC20 newToken = new Mock_ERC20("NEW", 18);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newToken), true, true, true);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for updateAsset:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_SetManagementFeeRate() public {
        uint256 gasStart = gasleft();
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(500); // 5%
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setManagementFeeRate:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_SetRedemptionFeeRate() public {
        uint256 gasStart = gasleft();
        vm.prank(admin);
        kpkSharesContract.setRedemptionFeeRate(250); // 2.5%
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setRedemptionFeeRate:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_SetPerformanceFeeRate() public {
        uint256 gasStart = gasleft();
        vm.prank(admin);
        kpkSharesContract.setPerformanceFeeRate(1000, address(usdc)); // 10%
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setPerformanceFeeRate:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_SetFeeReceiver() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        uint256 gasStart = gasleft();
        vm.prank(admin);
        kpkSharesContract.setFeeReceiver(newFeeReceiver);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setFeeReceiver:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_SetSubscriptionRequestTtl() public {
        uint256 gasStart = gasleft();
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(2 days);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setSubscriptionRequestTtl:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_SetRedemptionRequestTtl() public {
        uint256 gasStart = gasleft();
        vm.prank(admin);
        kpkSharesContract.setRedemptionRequestTtl(2 days);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setRedemptionRequestTtl:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    // ============================================================================
    // Batch Processing Gas Tests
    // ============================================================================

    function testGas_ProcessMultipleSubscriptionRequests() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        // Create multiple subscription requests
        uint256[] memory requestIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            requestIds[i] = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);
        }

        uint256[] memory approveRequests = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            approveRequests[i] = requestIds[i];
        }
        uint256[] memory rejectRequests = new uint256[](0);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (5 requests):", gasUsed);
        console.log("Gas per request:", gasUsed / 5);
        assertTrue(gasUsed > 0);
    }

    function testGas_ProcessMultipleRedemptionRequests() public {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        // Create shares and multiple redemption requests
        uint256 requestIdSubscription = _createSharesForTesting(alice, shares * 5);
        assertEq(requestIdSubscription, 1);

        uint256[] memory approveRequests = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            // Use previewRedemption which accounts for redemption fees
            uint256 assetsOut = kpkSharesContract.previewRedemption(shares, price, address(usdc));
            vm.prank(alice);
            uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);
            approveRequests[i] = requestId;
        }

        uint256[] memory rejectRequests = new uint256[](0);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (5 requests):", gasUsed);
        console.log("Gas per request:", gasUsed / 5);
        assertTrue(gasUsed > 0);
    }

    // ============================================================================
    // View Function Gas Tests
    // ============================================================================

    function testGas_GetRequest() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        // Create subscription request
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);

        uint256 gasStart = gasleft();
        kpkSharesContract.getRequest(requestId);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for getRequest:", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_AssetsToShares() public view {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;

        uint256 gasStart = gasleft();
        uint256 shares = kpkSharesContract.assetsToShares(assets, price, address(usdc));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for assetsToShares:", gasUsed);
        assertTrue(gasUsed > 0);
        assertTrue(shares > 0);
    }

    function testGas_SharesToAssets() public view {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        uint256 gasStart = gasleft();
        uint256 assets = kpkSharesContract.sharesToAssets(shares, price, address(usdc));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for sharesToAssets:", gasUsed);
        assertTrue(gasUsed > 0);
        assertTrue(assets > 0);
    }

    function testGas_GetApprovedAssets() public view {
        uint256 gasStart = gasleft();
        address[] memory assets = kpkSharesContract.getApprovedAssets();
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for getApprovedAssets:", gasUsed);
        assertTrue(gasUsed > 0);
        assertTrue(assets.length > 0);
    }

    function testGas_GetApprovedAsset() public view {
        uint256 gasStart = gasleft();
        IkpkShares.ApprovedAsset memory asset = kpkSharesContract.getApprovedAsset(address(usdc));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for getApprovedAsset:", gasUsed);
        assertTrue(gasUsed > 0);
        assertEq(asset.asset, address(usdc));
    }

    // ============================================================================
    // Fee Collection Gas Tests
    // ============================================================================

    function testGas_FeeCollection_WithManagementFee() public {
        uint256 assets = _usdcAmount(1000);
        uint256 price = SHARES_PRICE;
        uint256 sharesOut = kpkSharesContract.assetsToShares(assets, price, address(usdc));

        // Create subscription request
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestSubscription(assets, sharesOut, address(usdc), alice);

        // Fast forward to trigger management fee
        vm.warp(block.timestamp + 2 days);

        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (with management fee):", gasUsed);
        assertTrue(gasUsed > 0);
    }

    function testGas_FeeCollection_WithRedemptionFee() public {
        uint256 shares = _sharesAmount(1000);
        uint256 price = SHARES_PRICE;

        // Create shares and redemption request
        uint256 requestIdSubscription = _createSharesForTesting(alice, shares);
        assertEq(requestIdSubscription, 1);
        // Use previewRedemption which accounts for redemption fees
        uint256 assetsOut = kpkSharesContract.previewRedemption(shares, price, address(usdc));
        vm.prank(alice);
        uint256 requestId = kpkSharesContract.requestRedemption(shares, assetsOut, address(usdc), alice);

        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);

        uint256 gasStart = gasleft();
        vm.prank(ops);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for processRequests (with redemption fee):", gasUsed);
        assertTrue(gasUsed > 0);
    }
}
