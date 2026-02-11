// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./CapyfiBaseTest.sol";
import {Whitelist} from "src/contracts/Access/Whitelist.sol";
import {WhitelistAccess} from "src/contracts/Access/WhitelistAccess.sol";
import {TokenErrorReporter} from "src/contracts/ErrorReporter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {CErc20Delegator} from "src/contracts/CErc20Delegator.sol";
import {CErc20Delegate} from "src/contracts/CErc20Delegate.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title CTokenWhitelistTest
 * @notice Comprehensive tests for whitelist functionality in CToken, specifically for CErc20Delegator
 */
contract CTokenWhitelistTest is CapyfiBaseTest {
    // We'll test various whitelist scenarios
    Whitelist internal secondWhitelist;
    Whitelist internal secondWhitelistImplementation;
    MockERC20 internal mockERC20;
    CErc20Delegator internal cToken;
    CErc20Delegate internal implementation;

    // Events from CToken for testing
    event NewWhitelist(WhitelistAccess oldWhitelist, WhitelistAccess newWhitelist);

    function setUp() public override {
        super.setUp();
        
        // Create a second whitelist for testing changes
        vm.startPrank(admin);
        
        // Deploy second whitelist implementation
        secondWhitelistImplementation = new Whitelist();
        
        // Prepare initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            Whitelist.initialize.selector,
            admin
        );
        
        // Deploy the proxy contract
        ERC1967Proxy whitelistProxy = new ERC1967Proxy(
            address(secondWhitelistImplementation),
            initData
        );
        
        // Use the proxy address as our second whitelist
        secondWhitelist = Whitelist(address(whitelistProxy));
        
        // Deploy mock ERC20 for testing 
        mockERC20 = new MockERC20(admin, "Mock Token", "MOCK", 10000000 * 10 ** 18, 18);
        mockERC20.mint(admin, 1000 ether);
        mockERC20.mint(user1, 100 ether);
        mockERC20.mint(user2, 100 ether);
        mockERC20.mint(attacker, 100 ether);
        
        // Deploy CErc20Delegate implementation
        implementation = new CErc20Delegate();
        
        // Deploy CErc20Delegator with the mock token
        cToken = new CErc20Delegator(
            address(mockERC20),             // underlying asset
            comptroller,                    // comptroller
            irModel,                        // interest rate model
            1e18,                           // initial exchange rate
            "Capyfi Mock Token",            // name
            "caMOCK",                        // symbol
            8,                              // decimals
            payable(admin),                 // admin
            address(implementation),        // implementation
            bytes("")                       // become implementation data
        );
        
        vm.stopPrank();
    }

    // ==================== ADMIN CONTROL TESTS ====================

    // Test activating and deactivating the whitelist
    function testActivateAndDeactivateWhitelist() public {
        vm.startPrank(admin);
        
        // Set up whitelist
        cToken._setWhitelist(whitelist);
        assertEq(address(cToken.whitelist()), address(whitelist), "whitelist should be set to whitelist");
        
        // Add user1 to the whitelist
        whitelist.addWhitelisted(user1);
        vm.stopPrank();
        
        // Verify whitelist is active by default
        assertTrue(whitelist.isActive(), "Whitelist should be active by default");
        
        // Verify user1 can mint and user2 cannot
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Deactivate the whitelist (admin only)
        vm.prank(admin);
        whitelist.deactivate();
        assertFalse(whitelist.isActive(), "Whitelist should be deactivated");
        
        // Now user2 should be able to mint
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether); // This should succeed now
        vm.stopPrank();
        assertGt(cToken.balanceOf(user2), 0, "user2 should be able to mint with whitelist deactivated");
        
        // Activate again and verify restrictions are back
        vm.prank(admin);
        whitelist.activate();
        assertTrue(whitelist.isActive(), "Whitelist should be activated");
        
        // user1 can mint but user2 cannot mint more
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        vm.startPrank(attacker);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
    
    function testSetWhitelistEmitsEvent() public {
        vm.prank(admin);
        
        vm.expectEmit(true, true, false, false); // Check first two indexed params
        emit NewWhitelist(WhitelistAccess(address(0)), whitelist);
        
        cToken._setWhitelist(whitelist);
    }
    
    function testCannotSetInvalidWhitelist() public {
        // Create a contract that's not a WhitelistAccess
        vm.prank(admin);
        
        // Using a generic expectRevert since we don't know the exact message
        vm.expectRevert();
        cToken._setWhitelist(WhitelistAccess(address(mockERC20)));
    }

    // ==================== OPERATION TESTS WITH WHITELIST ====================

    function testMintWithDifferentWhitelists() public {
        // Set first whitelist
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // Whitelist user1 in the first whitelist
        vm.prank(admin);
        whitelist.addWhitelisted(user1);
        
        // Whitelist user2 in the second whitelist
        vm.prank(admin);
        secondWhitelist.addWhitelisted(user2);
        
        // user1 can mint with first whitelist
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        assertGt(cToken.balanceOf(user1), 0, "user1 should mint with first whitelist");
        
        // user2 cannot mint with first whitelist
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Switch to second whitelist
        vm.prank(admin);
        cToken._setWhitelist(secondWhitelist);
        
        // Now user2 can mint
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        assertGt(cToken.balanceOf(user2), 0, "user2 should mint with second whitelist");
        
        // But user1 cannot
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
    
    function testAllMintMethodsRespectWhitelist() public {
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // Regular mint should fail for non-whitelisted
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Now whitelist user1
        vm.prank(admin);
        whitelist.addWhitelisted(user1);
        
        // Mint should work now
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        assertGt(cToken.balanceOf(user1), 0, "regular mint should work for whitelisted");
    }
    
    // ==================== _checkWhitelist MODIFIER TESTS ====================
    
    function testWhitelistRequiredForMintInternal() public {
        // The _checkWhitelist modifier is applied to mintInternal, which is called by mint()
        
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
    
    function testRemovingUserFromWhitelistBlocksMint() public {
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // Add user1 to whitelist
        vm.prank(admin);
        whitelist.addWhitelisted(user1);
        
        // User can mint
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        assertGt(cToken.balanceOf(user1), 0, "mint should succeed when whitelisted");
        vm.stopPrank();
        
        // Remove user from whitelist
        vm.prank(admin);
        whitelist.removeWhitelisted(user1);
        
        // User can no longer mint
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }

    // ==================== WHITELIST MANAGEMENT TESTS ====================
    
    function testWhitelistAdminManagement() public {
        // Test adding a new admin
        vm.prank(admin);
        whitelist.addAdmin(user1);
        assertTrue(whitelist.isAdmin(user1), "user1 should be admin");
        
        // The new admin should be able to add whitelisted users
        vm.prank(user1);
        whitelist.addWhitelisted(user2);
        assertTrue(whitelist.isWhitelisted(user2), "user2 should be whitelisted by new admin");
        
        // Test removing admin
        vm.prank(admin);
        whitelist.removeAdmin(user1);
        assertFalse(whitelist.isAdmin(user1), "user1 should no longer be admin");
        
        // Former admin should no longer be able to add users
        vm.prank(user1);
        vm.expectRevert("WhitelistAccess: caller does not have the ADMIN_ROLE");
        whitelist.addWhitelisted(attacker);
    }
    
    // ==================== INTERACTIONS WITH OTHER CTOKEN OPERATIONS ====================
    
    function testRedeemAndWhitelist() public {
        // Whitelist is not required for redeem operations, verify this
        
        // First mint some tokens (no whitelist required initially)
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 10 ether);
        cToken.mint(10 ether);
        uint256 initialBalance = cToken.balanceOf(user1);
        assertGt(initialBalance, 0, "user1 should have minted tokens");
        vm.stopPrank();
        
        // Now set whitelist but don't add user1
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // User1 should still be able to redeem their tokens
        vm.prank(user1);
        cToken.redeem(initialBalance / 2);
        
        assertLt(cToken.balanceOf(user1), initialBalance, "user1 should have redeemed tokens");
        
        // But they cannot mint more without being whitelisted
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
    
    function testTransferAndWhitelist() public {
        // Transfers should work regardless of whitelist status
        
        // First mint some tokens (no whitelist required initially)
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 10 ether);
        cToken.mint(10 ether);
        uint256 initialBalance = cToken.balanceOf(user1);
        vm.stopPrank();
        
        // Set whitelist but don't whitelist either user
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // User1 should be able to transfer to user2 even though neither is whitelisted
        vm.prank(user1);
        cToken.transfer(user2, initialBalance / 2);
        
        assertGt(cToken.balanceOf(user2), 0, "user2 should have received tokens");
        assertLt(cToken.balanceOf(user1), initialBalance, "user1 should have sent tokens");
    }
    
    // ==================== EDGE CASES & SECURITY TESTS ====================
    
    function testWhitelistDoesNotAffectExistingBalances() public {
        // User mints tokens before whitelist is enabled
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 5 ether);
        cToken.mint(5 ether);
        uint256 initialBalance = cToken.balanceOf(user1);
        vm.stopPrank();
        
        // Enable whitelist without adding user1
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // Verify user's balance is unaffected
        assertEq(cToken.balanceOf(user1), initialBalance, "balance should be unaffected by whitelist");
        
        // User should still be able to redeem, transfer, etc.
        vm.prank(user1);
        cToken.redeem(initialBalance / 2);
        assertLt(cToken.balanceOf(user1), initialBalance, "user should be able to redeem after whitelist enabled");
    }
    
    // Test switching between different whitelist implementations including deactivating
    function testSwitchingWhitelistProperlyUpdatesAccess() public {
        // Set up first whitelist with user1
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        vm.prank(admin);
        whitelist.addWhitelisted(user1);
        
        // Set up second whitelist with user2
        vm.prank(admin);
        secondWhitelist.addWhitelisted(user2);
        
        // Check user1 can mint and user2 cannot
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Now switch to second whitelist
        vm.prank(admin);
        cToken._setWhitelist(secondWhitelist);
        
        // Should be reversed - user2 can mint, user1 cannot
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Deactivate whitelist to allow all users
        vm.prank(admin);
        secondWhitelist.deactivate();
        
        // Now both users can mint
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Go back to first whitelist and activate it
        vm.startPrank(admin);
        cToken._setWhitelist(whitelist);
        whitelist.activate();
        vm.stopPrank();
        
        // Check access is restored to original state
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
    
    function testWhitelistUpgradeDoesNotAffectCTokenBehavior() public {
        // Set up whitelist for cToken
        vm.startPrank(admin);
        cToken._setWhitelist(whitelist);
        whitelist.addWhitelisted(user1);
        vm.stopPrank();
        
        // Verify user1 can mint
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // Admin creates new implementation and upgrades
        vm.startPrank(admin);
        Whitelist newImplementation = new Whitelist();
        whitelist.upgradeTo(address(newImplementation));
        vm.stopPrank();
        
        // User1 should still be whitelisted and can mint after upgrade
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // User2 still cannot mint
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
    

    // Test activating and deactivating whitelist to enable/disable checks
    function testDisableAndReenableWhitelistWithActivation() public {
        // 1. Set up initial whitelist and whitelisted user
        vm.startPrank(admin);
        cToken._setWhitelist(whitelist);
        whitelist.addWhitelisted(user1);
        vm.stopPrank();
        
        // 2. Verify non-whitelisted user can't mint
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // 3. Deactivate whitelist to disable checks
        vm.prank(admin);
        whitelist.deactivate();
        
        // 4. Verify any user can mint now
        vm.startPrank(user2);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        assertGt(cToken.balanceOf(user2), 0, "user2 should be able to mint with whitelist deactivated");
        vm.stopPrank();
        
        // 5. Activate whitelist to re-enable checks
        vm.prank(admin);
        whitelist.activate();
        
        // 6. Verify whitelist restrictions are back in place
        vm.startPrank(attacker);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
        
        // 7. Verify previously whitelisted user can still mint
        vm.startPrank(user1);
        mockERC20.approve(address(cToken), 1 ether);
        cToken.mint(1 ether);
        assertGt(cToken.balanceOf(user1), 0, "user1 should still be whitelisted after re-enabling");
        vm.stopPrank();
    }
    
    // Test non-admin cannot deactivate whitelist
    function testNonAdminCannotDeactivateWhitelist() public {
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // Non-admin attempts to deactivate
        vm.prank(attacker);
        vm.expectRevert("WhitelistAccess: caller does not have the ADMIN_ROLE");
        whitelist.deactivate();
        
        // Verify whitelist is still active
        assertTrue(whitelist.isActive(), "Whitelist should still be active");
    }

    function testWhitelistIsInactiveButExists() public {
        // Set up the whitelist
        vm.prank(admin);
        cToken._setWhitelist(whitelist);
        
        // Deactivate whitelist but keep it set
        vm.prank(admin);
        whitelist.deactivate();
        
        // Verify whitelist is inactive
        assertFalse(whitelist.isActive(), "Whitelist should be inactive");
        
        // Mint should work for anyone when whitelist is inactive
        address nonWhitelisted = address(0x123);
        
        // First, transfer some tokens to the non-whitelisted address
        vm.prank(admin);
        mockERC20.mint(nonWhitelisted, 5 ether);
        
        // Now try to mint with the non-whitelisted address
        vm.startPrank(nonWhitelisted);
        mockERC20.approve(address(cToken), 2 ether);
        uint256 beforeBalance = cToken.balanceOf(nonWhitelisted);
        
        // This should succeed because whitelist is inactive
        cToken.mint(2 ether);
        
        // Verify operation succeeded
        uint256 afterBalance = cToken.balanceOf(nonWhitelisted);
        assertGt(afterBalance, beforeBalance, "Balance should increase after minting with inactive whitelist");
        
        // Additional verification: Try re-activating whitelist and confirm restrictions are back
        vm.stopPrank();
        vm.prank(admin);
        whitelist.activate();
        
        // Now minting should fail
        vm.startPrank(nonWhitelisted);
        mockERC20.approve(address(cToken), 1 ether);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cToken.mint(1 ether);
        vm.stopPrank();
    }
} 