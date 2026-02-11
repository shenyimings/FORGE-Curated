// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./CapyfiBaseTest.sol"; 
import {Whitelist} from "src/contracts/Access/Whitelist.sol"; 
import {TokenErrorReporter} from "src/contracts/ErrorReporter.sol"; 
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title CEtherTest
 * @notice Test CEther with Whitelist contract
 */
contract CEtherTest is CapyfiBaseTest {
    // We'll use the whitelist from the base test
    
    function setUp() public override {
        super.setUp();
        // Base test already sets up whitelist and necessary roles
    }

    function testAdminCanSetWhitelist() public {
        // Initially, cEther.whitelist() should be address(0) or whatever default
        assertEq(address(cEther.whitelist()), address(0), "whitelist should be unset by default");

        // Admin calls _setWhitelist
        vm.prank(admin);
        cEther._setWhitelist(whitelist);

        // Now the cEther's whitelist is the new contract
        assertEq(address(cEther.whitelist()), address(whitelist), "whitelist should be newly set");
    }

    function testNonAdminCannotSetWhitelist() public {
        // user1 attempts to set the whitelist => revert
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenErrorReporter.SetWhitelistAdminOwnerCheck.selector));
        cEther._setWhitelist(whitelist);

        // Confirm it did not change
        assertEq(address(cEther.whitelist()), address(0), "whitelist must still be unset");
    }

    // ----------------------------------------------------
    // TEST: Mint with NO whitelist set
    //       If address(whitelist) == address(0), no checks
    // ----------------------------------------------------
    function testMintWithoutWhitelist() public {
        // cEther has no whitelist set => anyone can mint
        assertEq(address(cEther.whitelist()), address(0), "no whitelist set initially");

        // user1 tries to mint => should succeed
        vm.prank(user1);
        cEther.mint{value: 1 ether}();

        uint256 bal = cEther.balanceOf(user1);
        assertGt(bal, 0, "user1 should have minted cTokens");
    }

    // ----------------------------------------------------
    // TEST: Setting a whitelist and requiring it
    // ----------------------------------------------------
    function testMintFailsIfUserNotWhitelisted() public {
        // Admin sets the Whitelist contract
        vm.prank(admin);
        cEther._setWhitelist(whitelist);

        // user1 is not whitelisted (WHITELISTED_ROLE) => revert
        vm.prank(user1);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cEther.mint{value: 1 ether}();
    }

    function testMintSucceedsIfUserIsWhitelisted() public {
        // Admin sets the Whitelist contract
        vm.prank(admin);
        cEther._setWhitelist(whitelist);

        // admin (as an ADMIN) adds user1
        vm.prank(admin);
        whitelist.addWhitelisted(user1);

        // user1 is now whitelisted and can mint
        vm.prank(user1);
        cEther.mint{value: 2 ether}();

        // check cETH balance
        uint256 cBal = cEther.balanceOf(user1);
        assertGt(cBal, 0, "should have minted cETH tokens");
    }

    // ----------------------------------------------------
    // TEST: Directly sending ETH to cEther (receive/fallback)
    //       -> triggers mintInternal w/ _checkWhitelist
    // ----------------------------------------------------
    function testReceiveEtherRevertsIfSenderNotWhitelisted() public {
        // Admin sets the Whitelist contract
        vm.prank(admin);
        cEther._setWhitelist(whitelist);

        // user1 is not whitelisted => expect revert
        vm.prank(user1);
        // vm.expectRevert("WhitelistAccess: not whitelisted");
        (bool success, ) = address(cEther).call{value: 1 ether}("");
        assertFalse(success, "call should fail for non-whitelisted user");
    }


    function testReceiveEtherWorksForWhitelistedUser() public {
        // Admin sets the Whitelist contract
        vm.prank(admin);
        cEther._setWhitelist(whitelist);

        // add user1 to the whitelist
        vm.prank(admin);
        whitelist.addWhitelisted(user1);

        // user1 sends ETH directly to cEther => should succeed
        vm.prank(user1);
        (bool success, ) = address(cEther).call{value: 3 ether}("");
        assertTrue(success, "call should succeed for whitelisted user");

        // check cToken balance
        uint256 cBal = cEther.balanceOf(user1);
        assertGt(cBal, 0, "user1 should have minted via receive()");
    }

    // ----------------------------------------------------
    // TEST: Changing the whitelist mid-lifecycle
    // ----------------------------------------------------
    function testChangingWhitelistRemovesOldUser() public {
        // Step 1: Admin sets the Whitelist contract
        vm.startPrank(admin);
        cEther._setWhitelist(whitelist);
        // user1 is whitelisted
        whitelist.addWhitelisted(user1);
        vm.stopPrank();

        // user1 can mint
        vm.prank(user1);
        cEther.mint{value: 1 ether}();
        uint oldBal = cEther.balanceOf(user1);
        assertGt(oldBal, 0, "user1 minted under current whitelist");

        // Deploy a new Whitelist instance
        vm.startPrank(admin);
        // Deploy whitelist implementation
        Whitelist secondWhitelistImpl = new Whitelist();
        
        // Prepare initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            Whitelist.initialize.selector,
            admin
        );
        
        // Deploy the proxy contract
        ERC1967Proxy whitelistProxy = new ERC1967Proxy(
            address(secondWhitelistImpl),
            initData
        );
        
        // Use the proxy address as our second whitelist
        Whitelist secondList = Whitelist(address(whitelistProxy));
        
        // secondList only whitelists user2, not user1
        secondList.addWhitelisted(user2);

        // Step 2: Admin changes the cEther's whitelist to secondList
        cEther._setWhitelist(secondList);
        vm.stopPrank();

        // user1 is no longer whitelisted => revert
        vm.prank(user1);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cEther.mint{value: 1 ether}();

        // user2 can now mint
        vm.prank(user2);
        cEther.mint{value: 2 ether}();
        assertGt(cEther.balanceOf(user2), 0, "user2 minted from new whitelist");
    }
    
    // ----------------------------------------------------
    // TEST: Whitelist deactivation and upgrades
    // ----------------------------------------------------
    function testDeactivateWhitelistAllowsAllMints() public {
        // Admin sets the Whitelist contract
        vm.prank(admin);
        cEther._setWhitelist(whitelist);
        
        // user1 is not whitelisted and cannot mint
        vm.prank(user1);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cEther.mint{value: 1 ether}();
        
        // Admin deactivates the whitelist
        vm.prank(admin);
        whitelist.deactivate();
        
        // Now user1 should be able to mint
        vm.prank(user1);
        cEther.mint{value: 1 ether}();
        assertGt(cEther.balanceOf(user1), 0, "user1 should be able to mint with whitelist deactivated");
    }
    
    function testWhitelistUpgradePreservesState() public {
        // Admin sets up whitelist and adds user1
        vm.startPrank(admin);
        cEther._setWhitelist(whitelist);
        whitelist.addWhitelisted(user1);
        vm.stopPrank();
        
        // user1 can mint
        vm.prank(user1);
        cEther.mint{value: 1 ether}();
        
        // Deploy new implementation and upgrade
        vm.startPrank(admin);
        Whitelist newImplementation = new Whitelist();
        whitelist.upgradeTo(address(newImplementation));
        vm.stopPrank();
        
        // user1 should still be whitelisted after upgrade
        vm.prank(user1);
        cEther.mint{value: 1 ether}();
        
        // user2 should still not be whitelisted
        vm.prank(user2);
        vm.expectRevert("WhitelistAccess: not whitelisted");
        cEther.mint{value: 1 ether}();
    }
}
