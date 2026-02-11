// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Tests for kpkShares initialization and constructor functionality
contract kpkSharesInitializationTest is kpkSharesTestBase {
    WatermarkFee public customPerfFeeModule;

    function setUp() public virtual override {
        super.setUp();
        customPerfFeeModule = new WatermarkFee();
    }

    // ============================================================================
    // Basic Initialization Tests
    // ============================================================================

    function testInitializeWithValidParameters() public view {
        // Test that the contract initializes correctly with valid parameters
        assertEq(kpkSharesContract.name(), "kpk");
        assertEq(kpkSharesContract.symbol(), "kpk");
        assertTrue(kpkSharesContract.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertEq(address(kpkSharesContract.portfolioSafe()), safe);
        assertEq(kpkSharesContract.subscriptionRequestTtl(), SUBSCRIPTION_TTL);
        assertEq(kpkSharesContract.redemptionRequestTtl(), REDEMPTION_TTL);
        assertEq(kpkSharesContract.feeReceiver(), feeRecipient);
        assertEq(kpkSharesContract.managementFeeRate(), MANAGEMENT_FEE_RATE);
        assertEq(kpkSharesContract.redemptionFeeRate(), REDEMPTION_FEE_RATE);
        assertEq(kpkSharesContract.performanceFeeRate(), PERFORMANCE_FEE_RATE);
        assertEq(address(kpkSharesContract.performanceFeeModule()), address(perfFeeModule));
    }

    function testInitializeWithEmptyName() public {
        // Test initialization with empty name (should succeed as contract doesn't validate empty strings)
        address kpkSharesImpl = address(new KpkShares());
        address kpkSharesProxy = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
        KpkShares kpkSharesEmptyName = KpkShares(kpkSharesProxy);

        // Should succeed and have empty name
        assertEq(kpkSharesEmptyName.name(), "");
    }

    function testInitializeWithEmptySymbol() public {
        // Test initialization with empty symbol (should succeed as contract doesn't validate empty strings)
        address kpkSharesImpl = address(new KpkShares());
        address kpkSharesProxy = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
        KpkShares kpkSharesEmptySymbol = KpkShares(kpkSharesProxy);

        // Should succeed and have empty symbol
        assertEq(kpkSharesEmptySymbol.symbol(), "");
    }

    function testInitializeWithZeroAddressAsset() public {
        // Test initialization with zero address asset (should revert)
        address kpkSharesImpl = address(new KpkShares());

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(0),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
    }

    function testInitializeWithZeroAddressSafe() public {
        // Test initialization with zero address safe (should revert)
        address kpkSharesImpl = address(new KpkShares());

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: address(0),
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
    }

    function testInitializeWithZeroAddressAdmin() public {
        // Test initialization with zero address admin (should revert)
        address kpkSharesImpl = address(new KpkShares());

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: address(0),
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
    }

    function testInitializeWithZeroAddressFeeReceiver() public {
        // Test initialization with zero address fee receiver (should revert)
        address kpkSharesImpl = address(new KpkShares());

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: address(0),
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
    }

    function testInitializeWithZeroAddressPerfFeeModule() public {
        // Test initialization with zero address performance fee module (should succeed)
        address kpkSharesImpl = address(new KpkShares());

        address kpkSharesProxy = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(0),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
        KpkShares kpkSharesZeroPerfFee = KpkShares(kpkSharesProxy);

        // Should succeed and have zero address for performance fee module
        assertEq(address(kpkSharesZeroPerfFee.performanceFeeModule()), address(0));
    }

    // ============================================================================
    // TTL Validation Tests
    // ============================================================================

    function testInitializeWithZeroDepositRequestTtl() public {
        // Test initialization with zero deposit request TTL (should revert)
        address kpkSharesImpl = address(new KpkShares());

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: 0,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
    }

    function testInitializeWithZeroRedeemRequestTtl() public {
        // Test initialization with zero redeem request TTL (should revert)
        address kpkSharesImpl = address(new KpkShares());

        vm.expectRevert(abi.encodeWithSelector(IkpkShares.InvalidArguments.selector));
        UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: 0,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
    }

    // ============================================================================
    // Fee Rate Validation Tests
    // ============================================================================

    function testInitializationParametersEdgeCases() public {
        // Test initialization with edge case fee parameters
        // These tests target the branches in _validateInitializationParams for fee rate validation
        // Updated to use new fee limits: Management/Redemption max 10%, Performance max 20%

        // Test with maximum management rate (should succeed)
        address kpkSharesImpl1 = address(new KpkShares());
        address kpkSharesProxy1 = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl1,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: 1000, // 10% in basis points (new maximum)
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
        KpkShares kpkSharesHighMgmt = KpkShares(kpkSharesProxy1);
        assertEq(kpkSharesHighMgmt.managementFeeRate(), 1000);

        // Test with maximum redeem fee (should succeed)
        address kpkSharesImpl2 = address(new KpkShares());
        address kpkSharesProxy2 = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl2,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: 1000, // 10% in basis points (new maximum)
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
        KpkShares kpkSharesHighRedeem = KpkShares(kpkSharesProxy2);
        assertEq(kpkSharesHighRedeem.redemptionFeeRate(), 1000);

        // Test with maximum performance fee (should succeed)
        address kpkSharesImpl3 = address(new KpkShares());
        address kpkSharesProxy3 = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl3,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(usdc),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: 2000 // 20% in basis points (new maximum)
                    }))
            )
        );
        KpkShares kpkSharesHighPerf = KpkShares(kpkSharesProxy3);
        assertEq(kpkSharesHighPerf.performanceFeeRate(), 2000);
    }

    // ============================================================================
    // Asset Validation Tests
    // ============================================================================

    function testInitializationWithValidDecimalsAsset() public {
        // Test initialization with an asset that has valid decimals (< 26)
        // This should succeed

        // Create a mock token with 25 decimals (just under the limit)
        Mock_ERC20 validDecimalsToken = new Mock_ERC20("VALID_DEC", 25);

        address kpkSharesImpl = address(new KpkShares());
        address kpkSharesProxy = UnsafeUpgrades.deployUUPSProxy(
            kpkSharesImpl,
            abi.encodeCall(
                KpkShares.initialize,
                (KpkShares.ConstructorParams({
                        asset: address(validDecimalsToken),
                        admin: admin,
                        name: "kpk",
                        symbol: "kpk",
                        safe: safe,
                        subscriptionRequestTtl: SUBSCRIPTION_TTL,
                        redemptionRequestTtl: REDEMPTION_TTL,
                        feeReceiver: feeRecipient,
                        managementFeeRate: MANAGEMENT_FEE_RATE,
                        redemptionFeeRate: REDEMPTION_FEE_RATE,
                        performanceFeeModule: address(perfFeeModule),
                        performanceFeeRate: PERFORMANCE_FEE_RATE
                    }))
            )
        );
        KpkShares kpkSharesValidDec = KpkShares(kpkSharesProxy);

        // Should succeed and have the asset approved
        assertTrue(kpkSharesValidDec.getApprovedAsset(address(validDecimalsToken)).canDeposit);
    }

    // ============================================================================
    // Role Assignment Tests
    // ============================================================================

    function testInitializationSetsCorrectRoles() public view {
        // Test that initialization sets the correct roles
        assertTrue(kpkSharesContract.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(kpkSharesContract.hasRole(OPERATOR, ops));
        assertFalse(kpkSharesContract.hasRole(OPERATOR, alice));
        assertFalse(kpkSharesContract.hasRole(OPERATOR, bob));
    }

    function testInitializationSetsCorrectOwner() public view {
        // Test that initialization sets the correct owner
        assertTrue(kpkSharesContract.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    // ============================================================================
    // State Initialization Tests
    // ============================================================================

    function testInitializationSetsCorrectState() public view {
        // Test that initialization sets the correct initial state
        assertTrue(kpkSharesContract.isApprovedAsset(address(usdc)));
        assertEq(kpkSharesContract.assetDecimals(address(usdc)), 6);
    }

    // ============================================================================
    // Reinitialization Protection Tests
    // ============================================================================

    function testCannotReinitialize() public {
        // Test that the contract cannot be reinitialized
        // The contract is already initialized in setUp(), so we can test reinitialization directly
        vm.expectRevert();
        kpkSharesContract.initialize(
            KpkShares.ConstructorParams({
                asset: address(usdc),
                admin: admin,
                name: "kpk2",
                symbol: "kpk2",
                safe: safe,
                subscriptionRequestTtl: SUBSCRIPTION_TTL,
                redemptionRequestTtl: REDEMPTION_TTL,
                feeReceiver: feeRecipient,
                managementFeeRate: MANAGEMENT_FEE_RATE,
                redemptionFeeRate: REDEMPTION_FEE_RATE,
                performanceFeeModule: address(perfFeeModule),
                performanceFeeRate: PERFORMANCE_FEE_RATE
            })
        );
    }
}
