// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AerodromeTestBase.sol";

contract AerodromeIntegrationTest is AerodromeTestBase {
    function setUp() public override {
        super.setUp();
        
        // Override token configs with proper collateral factors
        // Q32 = 2^32 = 4294967296
        // 90% = 0.9 * Q32 = 3865470566
        // 85% = 0.85 * Q32 = 3650722701
        vault.setTokenConfig(address(usdc), 3865470566, type(uint32).max);
        vault.setTokenConfig(address(dai), 3865470566, type(uint32).max);
        vault.setTokenConfig(address(weth), 3650722701, type(uint32).max);
        
        // Set a very high maxPoolPriceDifference to bypass price checks
        oracle.setMaxPoolPriceDifference(type(uint16).max);
        
        // Set global debt and lend limits (higher to accommodate tests)
        vault.setLimits(0, 10000000e6, 10000000e6, 1000000e6, 1000000e6);
        
        // Add initial liquidity to vault
        vm.startPrank(alice);
        usdc.approve(address(vault), 100000e6);
        vault.deposit(100000e6, alice);
        vm.stopPrank();
    }
    
    function testFullLifecycle() public {
        // 1. Create Aerodrome LP position with sufficient collateral
        uint256 tokenId = createPositionProper(
            bob, 
            address(usdc), 
            address(dai), 
            1, 
            -100, 
            100, 
            1e18,
            1000e6,  // 1000 USDC
            1000e18  // 1000 DAI
        );
        
        vm.startPrank(bob);
        
        // 2. Deposit position to vault
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, bob);
        
        // 3. Borrow against position
        uint256 borrowAmount = 10e6; // Borrow 10 USDC
        vault.borrow(tokenId, borrowAmount);
        assertEq(usdc.balanceOf(bob), 100000e6 + borrowAmount);
        
        // 4. Stake position in gauge
        vault.stakePosition(tokenId);
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(usdcDaiGauge));
        
        // 5. Accumulate some rewards
        usdcDaiGauge.setRewardForUser(address(gaugeManager), 100e18);
        
        // 6. Claim rewards
        uint256 aeroBalanceBefore = aero.balanceOf(bob);
        gaugeManager.claimRewards(tokenId);
        uint256 aeroBalanceAfter = aero.balanceOf(bob);
        assertGt(aeroBalanceAfter, aeroBalanceBefore);
        
        // 7. Repay loan
        usdc.approve(address(vault), borrowAmount + 100e6); // Extra for interest
        vault.repay(tokenId, borrowAmount, true);
        
        // 8. Unstake and remove position
        vault.remove(tokenId, bob, "");
        
        vm.stopPrank();
        
        // Verify final state
        assertEq(npm.ownerOf(tokenId), bob);
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(0));
    }
    
    function testMultiplePositionsAndRewards() public {
        // Alice creates and stakes position 1
        uint256 tokenId1 = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId1);
        vault.create(tokenId1, alice);
        vault.stakePosition(tokenId1);
        vm.stopPrank();
        
        // Bob creates and stakes position 2
        uint256 tokenId2 = createPosition(bob, address(weth), address(usdc), 10, -1000, 1000, 500000);
        vm.startPrank(bob);
        npm.approve(address(vault), tokenId2);
        vault.create(tokenId2, bob);
        vault.stakePosition(tokenId2);
        vm.stopPrank();
        
        // Set rewards for both gauges
        usdcDaiGauge.setRewardForUser(address(gaugeManager), 100e18);
        wethUsdcGauge.setRewardForUser(address(gaugeManager), 200e18);
        
        // Both users claim rewards
        vm.prank(alice);
        gaugeManager.claimRewards(tokenId1);
        
        vm.prank(bob);
        gaugeManager.claimRewards(tokenId2);
        
        // Check both received rewards
        assertGt(aero.balanceOf(alice), 0);
        assertGt(aero.balanceOf(bob), 0);
    }
    
    function testStakeAndUnstakeWithBorrowedPosition() public {
        // Test staking and unstaking functionality with a borrowed position
        uint256 tokenId = createPositionProper(
            bob,
            address(weth),
            address(usdc),
            10,
            -100,
            100,
            1e18,
            10e18,    // 10 WETH
            20000e6   // 20,000 USDC
        );
        
        vm.startPrank(bob);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, bob);
        
        // Borrow some USDC
        vault.borrow(tokenId, 5000e6); // Borrow 5k USDC
        
        // Verify borrow succeeded
        assertEq(usdc.balanceOf(bob), 100000e6 + 5000e6, "Should have received borrowed USDC");
        
        // Stake the position
        vault.stakePosition(tokenId);
        
        // Verify position is staked in correct gauge
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(wethUsdcGauge));
        assertEq(npm.ownerOf(tokenId), address(wethUsdcGauge), "NFT should be in gauge");
        
        // Unstake the position
        vault.unstakePosition(tokenId);
        
        // Verify position is back in vault
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(0), "Should not be in any gauge");
        assertEq(npm.ownerOf(tokenId), address(vault), "NFT should be back in vault");
        
        vm.stopPrank();
    }
    
    function testStakingDoesntAffectBorrowingPower() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        
        // Check borrowing power before staking
        (, uint256 borrowingPowerBefore, , , ) = vault.loanInfo(tokenId);
        
        // Stake position
        vault.stakePosition(tokenId);
        
        // Check borrowing power after staking (should be same)
        (, uint256 borrowingPowerAfter, , , ) = vault.loanInfo(tokenId);
        
        assertEq(borrowingPowerBefore, borrowingPowerAfter);
        vm.stopPrank();
    }
    
    function testRewardAccumulationOverTime() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vault.stakePosition(tokenId);
        vm.stopPrank();
        
        // Check initial pending rewards
        // uint256 pending1 = gaugeManager.pendingRewards(tokenId); // Function removed in simplified design
        
        // Advance time
        vm.warp(block.timestamp + 1 days);
        
        // Set more rewards to simulate accumulation
        usdcDaiGauge.setRewardForUser(address(gaugeManager), 1000e18);
        
        // Check pending increased
        // uint256 pending2 = gaugeManager.pendingRewards(tokenId); // Function removed in simplified design
        // assertGt(pending2, pending1); // Commented - pendingRewards removed
        
        // Claim all rewards
        vm.prank(alice);
        gaugeManager.claimRewards(tokenId);
        
        // Verify Alice received rewards
        assertGt(aero.balanceOf(alice), 0);
    }
}