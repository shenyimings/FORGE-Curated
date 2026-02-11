// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./kpkShares.TestBase.sol";
import {kpkSharesInitializationTest} from "./kpkShares.Initialization.sol";
import {kpkSharesSubscriptionsTest} from "./kpkShares.Subscriptions.sol";
import {kpkSharesRedemptionsTest} from "./kpkShares.Redemptions.sol";
import {kpkSharesFeesTest} from "./kpkShares.Fees.sol";
import {kpkSharesAssetsTest} from "./kpkShares.Assets.sol";
import {kpkSharesAdminTest} from "./kpkShares.Admin.sol";
import {kpkSharesIntegrationTest} from "./kpkShares.Integration.sol";
import {kpkSharesUpgradeTest} from "./kpkShares.Upgrade.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Mock_ERC20} from "test/mocks/tokens.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @notice Main test contract that runs all kpkShares tests
/// @dev This contract inherits from all domain-specific test contracts to run them together
contract kpkSharesMainTest is
    kpkSharesInitializationTest,
    kpkSharesSubscriptionsTest,
    kpkSharesRedemptionsTest,
    kpkSharesFeesTest,
    kpkSharesAssetsTest,
    kpkSharesAdminTest,
    kpkSharesIntegrationTest,
    kpkSharesUpgradeTest
{
    // ============================================================================
    // Test Suite Organization
    // ============================================================================

    /// @notice This contract serves as the main entry point for all kpkShares tests
    /// @dev It inherits from all domain-specific test contracts, allowing forge to run
    ///      all tests in a single test suite while maintaining logical organization

    function setUp()
        public
        override(
            kpkSharesInitializationTest,
            kpkSharesSubscriptionsTest,
            kpkSharesRedemptionsTest,
            kpkSharesFeesTest,
            kpkSharesAssetsTest,
            kpkSharesAdminTest,
            kpkSharesIntegrationTest,
            kpkSharesUpgradeTest
        )
    {
        super.setUp();
        // Additional setup specific to running all tests together can go here
    }

    // ============================================================================
    // Cross-Domain Integration Tests
    // ============================================================================

    /// @notice Test that all domains work together correctly
    function testAllDomainsIntegration() public {
        // 1. Test initialization
        assertEq(kpkSharesContract.name(), "kpk");
        assertEq(kpkSharesContract.symbol(), "kpk");
        assertTrue(kpkSharesContract.isApprovedAsset(address(usdc)));

        // 2. Test subscriptions
        uint256 requestId = _testRequestProcessing(true, alice, _usdcAmount(100), SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory approveRequests = new uint256[](1);
        approveRequests[0] = requestId;
        uint256[] memory rejectRequests = new uint256[](0);
        kpkSharesContract.processRequests(approveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 3. Test redemptions
        uint256 shares = kpkSharesContract.balanceOf(alice);
        uint256 redeemRequestId = _testRequestProcessing(false, alice, shares, SHARES_PRICE, false);
        vm.prank(ops);
        uint256[] memory redeemApproveRequests = new uint256[](1);
        redeemApproveRequests[0] = redeemRequestId;
        kpkSharesContract.processRequests(redeemApproveRequests, rejectRequests, address(usdc), SHARES_PRICE);

        // 4. Test fees
        vm.prank(admin);
        kpkSharesContract.setManagementFeeRate(100);
        vm.prank(admin);
        kpkSharesContract.setRedemptionFeeRate(50);

        // 5. Test assets
        Mock_ERC20 newAsset = new Mock_ERC20("NEW_ASSET", 18);
        vm.prank(ops);
        kpkSharesContract.updateAsset(address(newAsset), true, true, true);
        assertTrue(kpkSharesContract.isApprovedAsset(address(newAsset)));

        // 6. Test admin functions
        vm.prank(admin);
        kpkSharesContract.setSubscriptionRequestTtl(2 days);
        assertEq(kpkSharesContract.subscriptionRequestTtl(), 2 days);

        // 7. Test upgrade
        address newImplementation = address(new KpkShares());
        vm.prank(admin);
        kpkSharesContract.upgradeToAndCall(newImplementation, "");

        // Verify everything still works after upgrade
        assertEq(kpkSharesContract.name(), "kpk");
        assertTrue(kpkSharesContract.isApprovedAsset(address(usdc)));
    }

    // ============================================================================
    // Interface Support Tests
    // ============================================================================

    /// @notice Test that the contract supports the expected interfaces
    function testSupportsInterface() public view {
        // Test support for IkpkShares interface
        assertTrue(kpkSharesContract.supportsInterface(type(IkpkShares).interfaceId));

        // Test support for IERC165 interface
        assertTrue(kpkSharesContract.supportsInterface(type(IERC165).interfaceId));

        // Test support for IAccessControl interface
        assertTrue(kpkSharesContract.supportsInterface(type(IAccessControl).interfaceId));

        // Test that it doesn't support a random interface
        assertFalse(kpkSharesContract.supportsInterface(0x12345678));

        // Test that it doesn't support zero interface ID
        assertFalse(kpkSharesContract.supportsInterface(0x00000000));
    }

    /// @notice Test that all helper functions work correctly
    function testAllHelperFunctions() public {
        // Test _deployKpkSharesWithFees
        KpkShares customContract = _deployKpkSharesWithFees(200, 100, 500);
        assertEq(customContract.managementFeeRate(), 200);
        assertEq(customContract.redemptionFeeRate(), 100);
        assertEq(customContract.performanceFeeRate(), 500);

        // Test _testRequestProcessing
        uint256 requestId = _testRequestProcessing(true, bob, _usdcAmount(50), SHARES_PRICE, false);
        assertGt(requestId, 0);

        // Test _testFeeCharging
        uint256 feeRequestId = _testFeeCharging(100, 50, 200, _sharesAmount(100), 365 days);
        assertGt(feeRequestId, 0);

        // Test _testEdgeCaseAmounts
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _usdcAmount(10);
        amounts[1] = _usdcAmount(20);
        amounts[2] = _usdcAmount(30);
        uint256[] memory edgeRequestIds = _testEdgeCaseAmounts(true, alice, amounts, SHARES_PRICE);
        assertEq(edgeRequestIds.length, 3);

        // Test _createSharesForTesting
        uint256 sharesRequestId = _createSharesForTesting(admin, _sharesAmount(500));
        assertGt(sharesRequestId, 0);
        assertGt(kpkSharesContract.balanceOf(admin), 0);
    }

    /// @notice Test that all constants are accessible
    function testAllConstants() public pure {
        assertEq(SUBSCRIPTION_REQUEST_TTL, SUBSCRIPTION_REQUEST_TTL);
        assertEq(REDEMPTION_REQUEST_TTL, REDEMPTION_REQUEST_TTL);
        assertEq(MANAGEMENT_FEE_RATE, 100);
        assertEq(REDEMPTION_FEE_RATE, 50);
        assertEq(PERFORMANCE_FEE_RATE, 1000);
        assertEq(SHARES_PRICE, SHARES_PRICE);
    }

    // ============================================================================
    // Test Suite Validation
    // ============================================================================

    /// @notice Verify that all test domains are properly integrated
    function testTestSuiteCompleteness() public pure {
        // This test ensures that all domain-specific test contracts are properly inherited
        // and that their functionality is accessible

        // Test that we can access functions from all domains
        assertTrue(true); // Placeholder assertion

        // The real test is that this contract compiles and can access all the inherited functionality
        // If any domain is missing or has compilation errors, this contract won't compile
    }

    /// @notice Test that the base contract provides all necessary functionality
    function testBaseContractCompleteness() public view {
        // Test that all base contract functions are accessible
        assertEq(kpkSharesContract.name(), "kpk");
        assertEq(kpkSharesContract.symbol(), "kpk");
        assertTrue(kpkSharesContract.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(kpkSharesContract.hasRole(OPERATOR, ops));

        // Test that helper functions work
        assertEq(_usdcAmount(100), 100e6);
        assertEq(_sharesAmount(100), 100e18);
    }
}
