pragma solidity ^0.8.0;

import "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import "contracts/modules/FreezeThawModule.sol";
import "contracts/modules/PauseModule.sol";
import "frax-std/FraxTest.sol";

contract FrxUSDOFTUpgradeableTest is FraxTest {

    FrxUSDOFTUpgradeable oft;
    address al = vm.addr(0x41);
    address bob = vm.addr(0xb0b);
    address carl = vm.addr(0xc421);

    function setUp() external {
        oft = new FrxUSDOFTUpgradeable(address(0));
    }

    // ---------------------------------------------------
    // PauseModule tests
    // ---------------------------------------------------

    function test_Pause_succeeds() external {
        assertFalse(oft.isPaused());
        vm.prank(oft.owner());
        oft.pause();
        assertTrue(oft.isPaused());
    }

    function test_Pause_IsPaused_reverts() external {
        vm.startPrank(oft.owner());
        oft.pause();
        vm.expectRevert(PauseModule.IsPaused.selector);
        oft.pause();
    }

    function test_Pause_OnlyOwner() external {
        vm.prank(al);
        vm.expectRevert();
        oft.pause();
    }

    function test_Unpause_succeeds() external {
        vm.startPrank(oft.owner());
        oft.pause();
        oft.unpause();
        assertFalse(oft.isPaused());
    }

    function test_Unpause_NotPaused_reverts() external {
        vm.prank(oft.owner());
        vm.expectRevert(PauseModule.NotPaused.selector);
        oft.unpause();
    }

    function test_Unpause_OnlyOwner() external {
        vm.prank(oft.owner());
        oft.pause();

        vm.prank(al);
        vm.expectRevert();
        oft.unpause();
    }

    // ---------------------------------------------------
    // FreezeThawModule tests
    // ---------------------------------------------------

    function test_AddFreezer_succeeds() external {
        assertFalse(oft.isFreezer(al), "Al is not yet a freezer");
        address[] memory freezers = oft.freezers();
        assertEq(freezers.length, 0, "Freezers should be empty");
        
        vm.prank(oft.owner());
        oft.addFreezer(al);

        assertTrue(oft.isFreezer(al), "Al is now a freezer");
        freezers = oft.freezers();
        assertEq(freezers.length, 1, "Freezers should now contain al");
        assertEq(freezers[0], al);
    }

    function test_AddFreezer_AlreadyFreezer_reverts() external {
        vm.startPrank(oft.owner());
        
        oft.addFreezer(al);
        vm.expectRevert(FreezeThawModule.AlreadyFreezer.selector);
        oft.addFreezer(al);
    }

    function test_AddFreezer_OnlyOwner() external {
        assertTrue(al != oft.owner());
        vm.prank(al);
        vm.expectRevert();
        oft.addFreezer(al);
    }

    function test_RemoveFreezer_succeeds() external {
        vm.startPrank(oft.owner());

        oft.addFreezer(al);
        oft.removeFreezer(al);

        assertFalse(oft.isFreezer(al), "Al should no longer be a freezer");
        address[] memory freezers = oft.freezers();
        assertEq(freezers.length, 0, "Freezers should be empty");
    }

    function test_RemoveFreezer_NotFreezer_reverts() external {
        vm.prank(oft.owner());

        vm.expectRevert(FreezeThawModule.NotFreezer.selector);
        oft.removeFreezer(al);
    }

    function test_RemoveFreezer_OnlyOwner() external {
        vm.prank(oft.owner());
        oft.addFreezer(al);

        vm.prank(bob);
        vm.expectRevert();
        oft.removeFreezer(al);
    }

    function test_FreezeAsFreezer_succeeds() external {
        vm.prank(oft.owner());
        oft.addFreezer(al);

        assertFalse(oft.isFrozen(bob), "Bob should not yet be frozen");
        address[] memory frozen = oft.frozen();
        assertEq(frozen.length, 0, "Frozen should be empty");

        vm.prank(al);
        oft.freeze(bob);

        assertTrue(oft.isFrozen(bob), "Bob should now be frozen");
        frozen = oft.frozen();
        assertEq(frozen.length, 1, "Frozen should now contain bob");
        assertEq(frozen[0], bob);
    }

    function test_FreezeAsOwner_succeeds() external {
        assertFalse(oft.isFrozen(bob), "Bob should not yet be frozen");
        address[] memory frozen = oft.frozen();
        assertEq(frozen.length, 0, "Frozen should be empty");

        vm.prank(oft.owner());
        oft.freeze(bob);

        assertTrue(oft.isFrozen(bob), "Bob should now be frozen");
        frozen = oft.frozen();
        assertEq(frozen.length, 1, "Frozen should now contain bob");
        assertEq(frozen[0], bob);
    }

    function test_Freeze_AlreadyFrozen_succeeds() external {
        vm.prank(oft.owner());
        oft.addFreezer(al);

        vm.startPrank(al);
        oft.freeze(bob);
        oft.freeze(bob);
    }

    function test_Freeze_NotFreezer_reverts() external {
        assertFalse(oft.isFreezer(al));
        vm.expectRevert(FreezeThawModule.NotFreezer.selector);
        oft.freeze(bob);
    }

    function test_FreezeManyAsFreezer_succeeds() external {
        address[] memory accounts = new address[](2);
        accounts[0] = bob;
        accounts[1] = carl;

        vm.prank(oft.owner());
        oft.addFreezer(al);

        vm.prank(al);
        oft.freezeMany(accounts);
        
        address[] memory frozen = oft.frozen();
        assertEq(frozen.length, 2, "Should have frozen bob and carl");
    }

    function test_FreezeManyAsOwner_succeeds() external {
        address[] memory accounts = new address[](2);
        accounts[0] = bob;
        accounts[1] = carl;

        vm.prank(oft.owner());
        oft.freezeMany(accounts);
        
        address[] memory frozen = oft.frozen();
        assertEq(frozen.length, 2, "Should have frozen bob and carl");
    }


    function test_FreezeMany_NotFreezer_reverts() external {
        address[] memory accounts = new address[](2);
        accounts[0] = bob;
        accounts[1] = carl;
        
        assertFalse(oft.isFreezer(al));
        vm.expectRevert(FreezeThawModule.NotFreezer.selector);
        oft.freezeMany(accounts);
    }

    function test_Thaw_succeeds() external {
        vm.prank(oft.owner());
        oft.addFreezer(al);

        vm.prank(al);
        oft.freeze(bob);

        vm.prank(oft.owner());
        oft.thaw(bob);

        assertFalse(oft.isFrozen(bob));
        address[] memory frozen = oft.frozen();
        assertEq(frozen.length, 0);
    }

    function test_Thaw_NotFrozen_succeeds() external {
        vm.prank(oft.owner());
        oft.thaw(bob);
    }

    function test_ThawMany_succeeds() external {
        address[] memory accounts = new address[](2);
        accounts[0] = bob;
        accounts[1] = carl;

        vm.prank(oft.owner());
        oft.addFreezer(al);

        vm.prank(al);
        oft.freezeMany(accounts);

        vm.prank(oft.owner());
        oft.thawMany(accounts);
        assertFalse(oft.isFrozen(bob));
        assertFalse(oft.isFrozen(carl));
        address[] memory frozen = oft.frozen();
        assertEq(frozen.length, 0);
    }

    function test_Thaw_OnlyOwner() external {
        assertTrue(al != oft.owner());
        vm.prank(al);
        vm.expectRevert();
        oft.thaw(al);
    }

    function test_ThawMany_OnlyOwner() external {
        address[] memory accounts = new address[](2);
        accounts[0] = bob;
        accounts[1] = carl;

        assertTrue(al != oft.owner());
        vm.prank(al);
        vm.expectRevert();
        oft.thawMany(accounts);
    }

    // Before token transfer (using pause / freeze)
    function test_BeforeTokenTransferBlocked_reverts() external {
        deal(address(oft), al, 1e18);
        deal(address(oft), bob, 1e18);

        // paused check
        vm.prank(oft.owner());
        oft.pause();

        vm.prank(al);
        vm.expectRevert(FrxUSDOFTUpgradeable.BeforeTokenTransferBlocked.selector);
        oft.transfer(bob, 1e18);

        // unpause / freeze bob
        vm.startPrank(oft.owner());
        oft.unpause();
        oft.addFreezer(al);
        vm.stopPrank();
        vm.prank(al);
        oft.freeze(bob);

        // bob cannot send from his account
        vm.prank(bob);
        vm.expectRevert(FrxUSDOFTUpgradeable.BeforeTokenTransferBlocked.selector);
        oft.transfer(al, 1e18);

        // al cannot send to bob
        vm.prank(al);
        vm.expectRevert(FrxUSDOFTUpgradeable.BeforeTokenTransferBlocked.selector);
        oft.transfer(bob, 1e18);

        // bob cannot transferFrom al even with approval
        vm.prank(al);
        oft.approve(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(FrxUSDOFTUpgradeable.BeforeTokenTransferBlocked.selector);
        oft.transferFrom(al, bob, 1e18);
    }

    function test_BeforeTokenTransferBlocked_AsOwner_succeeds() external {
        deal(address(oft), al, 2e18);

        // give al ownership
        vm.prank(oft.owner());
        oft.transferOwnership(al);

        // succeeds when paused
        vm.startPrank(al);
        oft.pause();
        oft.transfer(bob, 1e18);

        // succeeds when frozen
        oft.addFreezer(al);
        oft.freeze(al);
        oft.transfer(bob, 1e18);
    }

    function test_Burn_OnlyOwner() external {
        deal(address(oft), al, 1e18);
        vm.prank(bob);
        vm.expectRevert();
        oft.burn(al, 0);
    }

    function test_Burn_PartialAmount_succeeds() external {
        deal(address(oft), al, 1e18);
        
        uint256 balanceBefore = oft.balanceOf(al);
        uint256 amount = 0.4e18;

        vm.prank(oft.owner());
        oft.burn(al, amount);

        assertEq(oft.balanceOf(al), balanceBefore - amount);
    }

    function test_Burn_FullAmount_succeeds() external {
        deal(address(oft), al, 1e18);

        vm.prank(oft.owner());
        oft.burn(al, 0);

        assertEq(oft.balanceOf(al), 0);
    }

    function test_BurnMany_ArrayMismatch_reverts() external {
        address[] memory accounts = new address[](1);
        uint256[] memory amounts = new uint256[](2);

        vm.prank(oft.owner());
        vm.expectRevert(FrxUSDOFTUpgradeable.ArrayMisMatch.selector);
        oft.burnMany(accounts, amounts);
    }

    function test_BurnMany_succeeds() external {
        deal(address(oft), al, 1e18);
        deal(address(oft), bob, 1e18);

        address[] memory accounts = new address[](2);
        accounts[0] = al;
        accounts[1] = bob;
        uint256[] memory amounts = new uint256[](2);

        vm.prank(oft.owner());
        oft.burnMany(accounts, amounts);
    }

    function test_BurnMany_OnlyOwner() external {
        deal(address(oft), al, 1e18);
        deal(address(oft), bob, 1e18);

        address[] memory accounts = new address[](2);
        accounts[0] = al;
        accounts[1] = bob;
        uint256[] memory amounts = new uint256[](2);

        vm.prank(al);
        vm.expectRevert();
        oft.burnMany(accounts, amounts);
    }
}
