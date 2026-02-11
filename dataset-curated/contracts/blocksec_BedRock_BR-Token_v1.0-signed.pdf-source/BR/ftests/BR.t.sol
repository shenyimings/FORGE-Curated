// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "../contracts/BR.sol";

contract BedrockTest is Test {
    Bedrock public br;
    address public admin;
    address public minter;
    address public freezer;
    address public user1;
    address public user2;
    address public freezeRecipient;

    function setUp() public {
        admin = address(1);
        minter = address(2);
        freezer = address(3);
        user1 = address(4);
        user2 = address(5);
        freezeRecipient = address(6);

        // Deploy contract
        vm.startPrank(admin);
        br = new Bedrock(admin, minter);

        // Set FREEZER_ROLE
        br.grantRole(br.FREEZER_ROLE(), freezer);

        // Set freezeToRecipient
        br.setFreezeToRecipient(freezeRecipient);
        vm.stopPrank();
    }

    // ============ Constructor Tests ============
    function testConstructor() public view {
        assertTrue(br.hasRole(br.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(br.hasRole(br.MINTER_ROLE(), minter));
        assertEq(br.name(), "Bedrock");
        assertEq(br.symbol(), "BR");
    }

    function testConstructorZeroAddress() public {
        vm.expectRevert("SYS001");
        new Bedrock(address(0), minter);

        vm.expectRevert("SYS001");
        new Bedrock(admin, address(0));
    }

    // ============ Minting Tests ============
    function testMint() public {
        vm.startPrank(minter);
        br.mint(user1, 1000);
        vm.stopPrank();
        assertEq(br.balanceOf(user1), 1000);
    }

    function testMintNotMinter() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(user1),
                " is missing role ",
                Strings.toHexString(uint256(br.MINTER_ROLE()), 32)
            )
        );
        br.mint(user1, 1000);
        vm.stopPrank();
    }

    // ============ Freezing Tests ============
    function testFreezeUsers() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.startPrank(freezer);
        br.freezeUsers(users);
        vm.stopPrank();

        assertTrue(br.frozenUsers(user1));
        assertTrue(br.frozenUsers(user2));
    }

    function testUnfreezeUsers() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.startPrank(freezer);
        br.freezeUsers(users);

        br.unfreezeUsers(users);
        vm.stopPrank();

        assertFalse(br.frozenUsers(user1));
        assertFalse(br.frozenUsers(user2));
    }

    function testFreezeUsersNotFreezer() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(user1),
                " is missing role ",
                Strings.toHexString(uint256(br.FREEZER_ROLE()), 32)
            )
        );
        br.freezeUsers(users);
        vm.stopPrank();
    }

    // ============ Transfer Tests ============
    function testTransfer() public {
        // Mint tokens first
        vm.startPrank(minter);
        br.mint(user1, 1000);
        vm.stopPrank();

        // Normal transfer
        vm.startPrank(user1);
        br.transfer(user2, 500);
        vm.stopPrank();
        assertEq(br.balanceOf(user1), 500);
        assertEq(br.balanceOf(user2), 500);
    }

    function testTransferFrozenUser() public {
        // Mint tokens first
        vm.startPrank(minter);
        br.mint(user1, 1000);
        vm.stopPrank();

        // Freeze user
        vm.startPrank(freezer);
        address[] memory users = new address[](1);
        users[0] = user1;
        br.freezeUsers(users);
        vm.stopPrank();

        // Test transfer to non-designated address
        vm.startPrank(user1);
        vm.expectRevert("USR016");
        br.transfer(user2, 500);
        vm.stopPrank();

        // Test transfer to designated address
        vm.startPrank(user1);
        br.transfer(freezeRecipient, 500);
        vm.stopPrank();
        assertEq(br.balanceOf(user1), 500);
        assertEq(br.balanceOf(freezeRecipient), 500);
    }

    // ============ Batch Transfer Tests ============
    function testBatchTransfer() public {
        // Mint tokens first
        vm.startPrank(minter);
        br.mint(user1, 1000);
        vm.stopPrank();

        address[] memory recipients = new address[](2);
        recipients[0] = user2;
        recipients[1] = freezeRecipient;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 300;
        amounts[1] = 400;

        vm.startPrank(user1);
        br.batchTransfer(recipients, amounts);
        vm.stopPrank();

        assertEq(br.balanceOf(user1), 300);
        assertEq(br.balanceOf(user2), 300);
        assertEq(br.balanceOf(freezeRecipient), 400);
    }

    function testBatchTransferEmptyArray() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(user1);
        vm.expectRevert("USR001");
        br.batchTransfer(recipients, amounts);
    }

    function testBatchTransferLengthMismatch() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(user1);
        vm.expectRevert("USR002");
        br.batchTransfer(recipients, amounts);
    }

    // ============ Admin Function Tests ============
    function testSetFreezeToRecipient() public {
        address newRecipient = address(7);

        vm.startPrank(admin);
        br.setFreezeToRecipient(newRecipient);
        vm.stopPrank();
        assertEq(br.freezeToRecipient(), newRecipient);
    }

    function testSetFreezeToRecipientNotAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(user1),
                " is missing role ",
                Strings.toHexString(uint256(br.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        br.setFreezeToRecipient(user2);
        vm.stopPrank();
    }
}
