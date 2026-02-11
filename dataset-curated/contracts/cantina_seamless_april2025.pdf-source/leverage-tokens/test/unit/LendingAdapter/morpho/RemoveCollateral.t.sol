// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorphoBase} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract MorphoLendingAdapterRemoveCollateralTest is MorphoLendingAdapterTest {
    function testFuzz_removeCollateral(uint256 amount) public {
        vm.assume(amount > 0);

        // Deal Morpho the required collateral token amount
        deal(address(collateralToken), address(morpho), amount);

        // Expect Morpho.withdrawCollateral to be called with the correct parameters
        vm.expectCall(
            address(morpho),
            abi.encodeCall(
                IMorphoBase.withdrawCollateral,
                (defaultMarketParams, amount, address(lendingAdapter), address(leverageManager))
            )
        );
        vm.prank(address(leverageManager));
        lendingAdapter.removeCollateral(amount);

        assertEq(collateralToken.balanceOf(address(leverageManager)), amount);
    }

    function test_removeCollateral_ZeroAmount() public {
        // Nothing should happen
        vm.prank(address(leverageManager));
        lendingAdapter.removeCollateral(0);
        assertEq(collateralToken.balanceOf(address(morpho)), 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_removeCollateral_RevertIf_NotLeverageManager(address caller) public {
        vm.assume(caller != address(leverageManager));

        vm.expectRevert(ILendingAdapter.Unauthorized.selector);
        vm.prank(caller);
        lendingAdapter.removeCollateral(1);
    }
}
