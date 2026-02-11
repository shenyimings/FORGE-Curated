// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorphoBase} from "@morpho-blue/interfaces/IMorpho.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract MorphoLendingAdapterBorrowTest is MorphoLendingAdapterTest {
    function testFuzz_borrow(uint256 amount) public {
        vm.assume(amount > 0);

        // Deal Morpho the required debt token amount
        deal(address(debtToken), address(morpho), amount);

        // Expect Morpho.borrow to be called with the correct parameters
        vm.expectCall(
            address(morpho),
            abi.encodeCall(
                IMorphoBase.borrow, (defaultMarketParams, amount, 0, address(lendingAdapter), address(leverageManager))
            )
        );

        vm.prank(address(leverageManager));
        lendingAdapter.borrow(amount);

        assertEq(debtToken.balanceOf(address(leverageManager)), amount);
    }

    function testFork_borrow_ZeroAmount() public {
        // Nothing happens
        vm.prank(address(leverageManager));
        lendingAdapter.borrow(0);
        assertEq(debtToken.balanceOf(address(leverageManager)), 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_borrow_RevertIf_NotLeverageManager(address caller) public {
        vm.assume(caller != address(leverageManager));

        vm.expectRevert(ILendingAdapter.Unauthorized.selector);
        vm.prank(caller);
        lendingAdapter.borrow(1);
    }

    function test_borrow_ZeroAmount() public {
        // Nothing should happen
        vm.prank(address(leverageManager));
        lendingAdapter.borrow(0);
        assertEq(debtToken.balanceOf(address(leverageManager)), 0);
    }
}
