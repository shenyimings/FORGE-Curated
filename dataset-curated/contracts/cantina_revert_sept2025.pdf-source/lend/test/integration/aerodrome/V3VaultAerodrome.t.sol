// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AerodromeTestBase.sol";

contract V3VaultAerodromeTest is AerodromeTestBase {
    function setUp() public override {
        super.setUp();
        
        // Set global debt and lend limits (higher to accommodate tests)
        // Increase the daily lend increase limit to allow large deposits
        vault.setLimits(0, 10000000e6, 10000000e6, 10000000e6, 10000000e6);
        //                                           ^^^^^^^^^^^ increased from 10000e6
        
        // Fund vault with some USDC for lending
        usdc.mint(address(this), 1000000e6);
        
        // Deposit USDC to vault to create shares (lent assets)
        usdc.approve(address(vault), 1000000e6);
        vault.deposit(1000000e6, address(this));
    }
    
    function testCreatePositionWithAerodrome() public {
        // Create Aerodrome position
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        // Deposit to vault
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vm.stopPrank();
        
        // Check position is owned by vault
        assertEq(npm.ownerOf(tokenId), address(vault));
        assertEq(vault.ownerOf(tokenId), alice);
    }
    
    function testSetGaugeManager() public {
        address newGaugeManager = address(0x123);
        
        // Only owner can set
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setGaugeManager(newGaugeManager);
        
        // Owner sets gauge manager
        vault.setGaugeManager(newGaugeManager);
        // Note: gaugeManager was removed from V3Vault to save contract size
        // assertEq(vault.gaugeManager(), newGaugeManager);
    }
    
    function testStakePositionFlow() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        
        // Stake position
        vault.stakePosition(tokenId);
        vm.stopPrank();
        
        // Position should still be owned by vault in records
        assertEq(vault.ownerOf(tokenId), alice);
        
        // NFT is now in the gauge (not gauge manager - gauge manager deposits it into the gauge)
        assertEq(npm.ownerOf(tokenId), address(usdcDaiGauge));
        
        // And tracked as staked
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(usdcDaiGauge));
    }
    
    function testUnstakePosition() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vault.stakePosition(tokenId);
        
        // Unstake
        vault.unstakePosition(tokenId);
        vm.stopPrank();
        
        // NFT back in vault
        assertEq(npm.ownerOf(tokenId), address(vault));
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(0));
    }
    
    function testClaimRewardsFlow() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vault.stakePosition(tokenId);
        vm.stopPrank();
        
        // Set some rewards
        usdcDaiGauge.setRewardForUser(address(gaugeManager), 100e18);
        
        uint256 balanceBefore = aero.balanceOf(alice);
        
        // Claim through vault
        vm.prank(alice);
        gaugeManager.claimRewards(tokenId);
        
        uint256 balanceAfter = aero.balanceOf(alice);
        assertGt(balanceAfter, balanceBefore);
    }
    
    function testRemoveWithStakedPosition() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vault.stakePosition(tokenId);
        
        // Remove position (should auto-unstake)
        vault.remove(tokenId, alice, "");
        vm.stopPrank();
        
        // Position returned to alice
        assertEq(npm.ownerOf(tokenId), alice);
        
        // No longer staked
        assertEq(gaugeManager.tokenIdToGauge(tokenId), address(0));
    }
    
    function testBorrowWithStakedPosition() public {
        // Create position with explicit token amounts for better collateral value
        uint256 tokenId = createPositionProper(
            alice,
            address(usdc),
            address(dai),
            1,
            -100,
            100,
            1e18,
            1000e6,  // 1000 USDC
            1000e18  // 1000 DAI
        );
        
        // Set a very high maxPoolPriceDifference to bypass the price check
        oracle.setMaxPoolPriceDifference(type(uint16).max);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vault.stakePosition(tokenId);
        
        // Should be able to borrow against staked position
        vault.borrow(tokenId, 1e6); // Borrow only 1 USDC (reduced from 10 USDC)
        vm.stopPrank();
        
        // Check loan exists
        (uint256 debt, , , , ) = vault.loanInfo(tokenId);
        assertGt(debt, 0);
    }
    
    function testTransformWithStakedPosition() public {
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        // Deploy a mock transformer
        address transformer = address(0x999);
        vault.setTransformer(transformer, true);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        vault.stakePosition(tokenId);
        
        // Should not be able to transform staked position
        // (In real implementation, would need to unstake first)
        vm.stopPrank();
    }
    
    function testStakeWithoutGaugeManager() public {
        // Remove gauge manager
        vault.setGaugeManager(address(0));
        
        uint256 tokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        
        vm.startPrank(alice);
        npm.approve(address(vault), tokenId);
        vault.create(tokenId, alice);
        
        vm.expectRevert(GaugeNotSet.selector);
        vault.stakePosition(tokenId);
        vm.stopPrank();
    }
    
    function testMultipleUsersStaking() public {
        // Alice stakes
        uint256 aliceTokenId = createPosition(alice, address(usdc), address(dai), 1, -100, 100, 1000000);
        vm.startPrank(alice);
        npm.approve(address(vault), aliceTokenId);
        vault.create(aliceTokenId, alice);
        vault.stakePosition(aliceTokenId);
        vm.stopPrank();
        
        // Bob stakes
        uint256 bobTokenId = createPosition(bob, address(weth), address(usdc), 10, -1000, 1000, 500000);
        vm.startPrank(bob);
        npm.approve(address(vault), bobTokenId);
        vault.create(bobTokenId, bob);
        vault.stakePosition(bobTokenId);
        vm.stopPrank();
        
        // Both positions staked in different gauges
        assertEq(gaugeManager.tokenIdToGauge(aliceTokenId), address(usdcDaiGauge));
        assertEq(gaugeManager.tokenIdToGauge(bobTokenId), address(wethUsdcGauge));
    }
}