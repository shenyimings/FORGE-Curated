// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import "forge-std/Test.sol";
import "test/mocks/ERC20Mock.sol";

contract ERC20MockTest is Test {
    ERC20Mock token;
    address admin = address(0x1);
    address user = address(0x2);
    address pohVerify = address(0x3);
    uint8 decimals = 18;
    uint256 mintLimit = 1000e18;

    function setUp() public {
        token = new ERC20Mock("TestToken", "TTK", decimals, admin, pohVerify, 1000e18);
    }

    function testDeployment() public view {
        assertEq(token.name(), "TestToken");
        assertEq(token.symbol(), "TTK");
        assertEq(token.decimals(), decimals);
        assertEq(token.admin(), admin);
        assertEq(token.pohVerify(), pohVerify);
        assertEq(token.mintLimit(), mintLimit);
    }

    function testSetOnlyVerify_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert(ERC20Mock.ERC20Mock_NotAuthorized.selector);
        token.setOnlyVerify(true);
    }

    function testSetOnlyVerify_Admin() public {
        vm.prank(admin);
        token.setOnlyVerify(true);
        assertTrue(token.onlyVerified());
    }

    function testMint_NotOnlyVerified() public {
        vm.prank(user);
        token.mint(user, mintLimit - 1);
        assertEq(token.balanceOf(user), mintLimit - 1);
        assertEq(token.minted(user), mintLimit - 1);
    }

    function testMint_ExceedsLimit() public {
        vm.prank(user);
        token.mint(user, mintLimit - 1);
        vm.prank(user);
        vm.expectRevert(ERC20Mock.ERC20Mock_AlreadyMinted.selector);
        token.mint(user, 2);
    }

    function testBurn_Success() public {
        vm.prank(user);
        token.mint(user, 500);
        vm.prank(user);
        token.burn(300);
        assertEq(token.balanceOf(user), 200);
        assertEq(token.minted(user), 500);
    }

    function testBurn_ExceedsBalance() public {
        vm.prank(user);
        token.mint(user, 500);
        vm.prank(user);
        vm.expectRevert(ERC20Mock.ERC20Mock_TooMuch.selector);
        token.burn(600);
    }

    function testBurnFrom_Admin() public {
        vm.prank(user);
        token.mint(user, 500);
        vm.prank(admin);
        token.burn(user, 300);
        assertEq(token.balanceOf(user), 200);
        assertEq(token.minted(user), 500);
    }

    function testBurnFrom_NotAdmin() public {
        vm.prank(user);
        token.mint(user, 500);
        vm.prank(user);
        vm.expectRevert(ERC20Mock.ERC20Mock_NotAuthorized.selector);
        token.burn(admin, 100);
    }
}
