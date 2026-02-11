// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ERC20Mintable, IERC20Mintable } from "../../../src/unit/ERC20Mintable.sol";

abstract contract ERC20MintableTest is Test {
    ERC20Mintable token;

    address owner = makeAddr("owner");

    function setUp() public virtual {
        token = new ERC20Mintable(owner, "name", "symbol");
    }
}

contract ERC20Mintable_Mint_Test is ERC20MintableTest {
    function testFuzz_shouldMint_whenOwner(address to, uint256 amount) public {
        vm.assume(to != address(0));

        vm.prank(owner);
        token.mint(to, amount);

        assertEq(token.totalSupply(), amount);
        assertEq(token.balanceOf(to), amount);
    }

    function testFuzz_shouldEmit_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));

        vm.expectEmit();
        emit IERC20Mintable.Mint(to, amount);

        vm.prank(owner);
        token.mint(to, amount);
    }

    function testFuzz_shouldRevert_whenNotOwner(address notOwner) public {
        vm.assume(notOwner != owner && notOwner != address(0));

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.mint(makeAddr("to"), 1);
    }

    function test_shouldRevert_whenToZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.mint(address(0), 1);
    }
}

contract ERC20Mintable_Burn_Test is ERC20MintableTest {
    address from = makeAddr("from");
    address spender = from;
    uint256 initialBalance = 100 ether;

    function setUp() public override {
        super.setUp();

        vm.prank(owner);
        token.mint(from, initialBalance);
    }

    function testFuzz_shouldBurn_whenOwner(uint256 amount) public {
        amount = bound(amount, 0, initialBalance);

        vm.prank(owner);
        token.burn(from, spender, amount);

        assertEq(token.totalSupply(), initialBalance - amount);
        assertEq(token.balanceOf(from), initialBalance - amount);
    }

    function test_shouldSpendAllowance() public {
        uint256 amount = initialBalance / 2;
        spender = makeAddr("spender");

        vm.prank(from);
        token.approve(spender, amount);

        vm.prank(owner);
        token.burn(from, spender, amount);

        assertEq(token.totalSupply(), initialBalance - amount);
        assertEq(token.balanceOf(from), initialBalance - amount);
        assertEq(token.allowance(from, spender), 0);
    }

    function testFuzz_shouldEmit_Burn(uint256 amount) public {
        amount = bound(amount, 0, initialBalance);

        vm.expectEmit();
        emit IERC20Mintable.Burn(from, amount);

        vm.prank(owner);
        token.burn(from, spender, amount);
    }

    function testFuzz_shouldRevert_whenNotOwner(address notOwner) public {
        vm.assume(notOwner != owner && notOwner != address(0));

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        token.burn(from, spender, 1);
    }

    function test_shouldRevert_whenFromZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.burn(address(0), spender, 1);
    }

    function testFuzz_shouldRevert_whenInsufficientBalance(uint256 amount) public {
        amount = bound(amount, initialBalance + 1, type(uint256).max);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, initialBalance, amount)
        );
        token.burn(from, spender, amount);
    }

    function test_shouldRevert_whenSpenderNotApproved() public {
        spender = makeAddr("spender");

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, initialBalance)
        );
        vm.prank(owner);
        token.burn(from, spender, initialBalance);
    }
}

contract ERC20Mintable_RenounceOwnership_Test is ERC20MintableTest {
    function test_shouldRevert_whenRenounceOwnership_whenOwner() public {
        vm.prank(owner);
        vm.expectRevert(ERC20Mintable.RenounceOwnershipDisabled.selector);
        token.renounceOwnership();
    }

    function testFuzz_shouldRevert_whenRenounceOwnership_whenNotOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        vm.prank(notOwner);
        vm.expectRevert(ERC20Mintable.RenounceOwnershipDisabled.selector);
        token.renounceOwnership();
    }
}
