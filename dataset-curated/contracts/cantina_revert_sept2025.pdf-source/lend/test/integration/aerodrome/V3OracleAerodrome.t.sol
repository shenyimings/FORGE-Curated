// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AerodromeTestBase.sol";

contract V3OracleAerodromeTest is AerodromeTestBase {
    function setUp() public override {
        super.setUp();
    }
    
    function testGetPoolWithAerodrome() public {
        // Test that oracle can retrieve Aerodrome pools correctly via token config
        (,,,,,IAerodromeSlipstreamPool pool,,,) = oracle.feedConfigs(address(dai));
        assertEq(address(pool), usdcDaiPool);
        
        (,,,,,pool,,,) = oracle.feedConfigs(address(weth));
        assertEq(address(pool), wethUsdcPool);
    }
    
    function testSetTokenConfigWithAerodromePool() public {
        // Create a new token
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);  // Added decimals parameter
        
        // Create a new pool
        address newPool = address(new MockPool(address(newToken), address(usdc), 60, 60));
        factory.setPool(address(newToken), address(usdc), 60, newPool);
        
        // Create price feed
        MockChainlinkAggregator newFeed = new MockChainlinkAggregator(5e8, 8); // $5
        
        // Set token config with Aerodrome pool
        oracle.setTokenConfig(
            address(newToken),
            AggregatorV3Interface(address(newFeed)),
            3600,
            IAerodromeSlipstreamPool(newPool),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            200
        );
        
        // Verify config was set
        (AggregatorV3Interface feed, uint32 maxFeedAge,,,,IAerodromeSlipstreamPool twapPool,,,) = oracle.feedConfigs(address(newToken));
        assertEq(address(feed), address(newFeed));
        assertEq(maxFeedAge, 3600);
        assertEq(address(twapPool), newPool);
    }
    
    function testGetValueWithAerodromePosition() public {
        // Create a position
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        // Set a very high maxPoolPriceDifference to bypass the price check
        oracle.setMaxPoolPriceDifference(type(uint16).max);
        
        // Get position value
        (uint256 value, uint256 feeValue, uint256 price0X96, uint256 price1X96) = oracle.getValue(tokenId, address(usdc));
        
        // Should have some value from tokensOwed
        assertGt(value, 0);
        assertGt(price0X96, 0);
        assertGt(price1X96, 0);
    }
    
    // Removed testTickSpacingToFeeConversion - no conversion needed
    // Aerodrome uses tickSpacing directly, not fee tiers
    
    function testPriceCalculationWithTWAP() public {
        // Test that price calculation works with Aerodrome pools
        // Create a position first
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        // Set a very high maxPoolPriceDifference to bypass the price check
        oracle.setMaxPoolPriceDifference(type(uint16).max);
        
        (uint256 price, , , ) = oracle.getValue(tokenId, address(usdc));
        
        // Price should be greater than 0
        assertGt(price, 0);
    }
    
    function testEmergencyAdminFunctions() public {
        // Test only owner can set emergency admin
        address emergencyAdmin = address(0x999);
        
        // Non-owner cannot set emergency admin
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setEmergencyAdmin(emergencyAdmin);
        
        // Owner can set emergency admin
        oracle.setEmergencyAdmin(emergencyAdmin);
        
        // Emergency admin can update oracle mode
        vm.prank(emergencyAdmin);
        oracle.setOracleMode(address(usdc), V3Oracle.Mode.CHAINLINK);
        
        (,,,,,,,V3Oracle.Mode mode,) = oracle.feedConfigs(address(usdc));
        assertEq(uint8(mode), uint8(V3Oracle.Mode.CHAINLINK));
    }
    
    function testPoolAddressResolution() public {
        // Test that factory correctly resolves pool addresses
        
        // For token pair that exists
        address resolvedPool = factory.getPool(address(usdc), address(dai), 1);
        assertEq(resolvedPool, usdcDaiPool);
        
        // For token pair that doesn't exist
        address nonExistentPool = factory.getPool(address(usdc), address(aero), 1);
        assertEq(nonExistentPool, address(0));
    }
    
    function testPositionValueCalculation() public {
        // Create position with correct token amounts
        // WETH has 18 decimals, USDC has 6 decimals
        uint128 wethAmount = 0.05e18; // 0.05 WETH
        uint128 usdcAmount = 100e6;   // 100 USDC
        
        uint256 tokenId = createPositionProper(
            alice, 
            address(weth), 
            address(usdc), 
            10, 
            -1000, 
            1000, 
            500000,
            wethAmount,
            usdcAmount
        );
        
        // Set a very high maxPoolPriceDifference to bypass the price check
        oracle.setMaxPoolPriceDifference(type(uint16).max);
        
        // Get value in USDC
        (uint256 value, , , ) = oracle.getValue(tokenId, address(usdc));
        
        // Expected: 0.05 WETH * $2000 + 100 USDC = $100 + $100 = $200
        uint256 expectedValue = (wethAmount * 2000e6 / 1e18) + usdcAmount;
        
        assertApproxEqRel(value, expectedValue, 0.01e18); // 1% tolerance
    }
}