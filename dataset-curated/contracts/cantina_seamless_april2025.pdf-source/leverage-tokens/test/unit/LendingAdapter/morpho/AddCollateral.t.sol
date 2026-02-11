// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorpho, IMorphoBase} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract MorphoLendingAdapterAddCollateralTest is MorphoLendingAdapterTest {
    address public alice = makeAddr("alice");

    function testFuzz_addCollateral(uint256 amount) public {
        vm.assume(amount > 0);

        // Deal alice the required collateral
        deal(address(collateralToken), alice, amount);

        // Alice approves the lending adapter to spend her assets
        vm.startPrank(alice);
        collateralToken.approve(address(lendingAdapter), amount);

        // Expect the Alice's assets to be transferred to the lending adapter
        vm.expectCall(
            address(collateralToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(lendingAdapter), amount)
        );
        // Expect LendingAdapter.addCollateral to approve the morpho market to spend the assets for the amount
        vm.expectCall(
            address(collateralToken), abi.encodeWithSelector(IERC20.approve.selector, address(morpho), amount)
        );
        // Expect Morpho.supplyCollateral to be called with the correct parameters
        vm.expectCall(
            address(morpho),
            abi.encodeCall(IMorphoBase.supplyCollateral, (defaultMarketParams, amount, address(lendingAdapter), hex""))
        );

        lendingAdapter.addCollateral(amount);
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(address(morpho)), amount);
    }

    function test_addCollateral_ZeroAmount() public {
        // Nothing happens
        lendingAdapter.addCollateral(0);
        assertEq(collateralToken.balanceOf(address(morpho)), 0);
    }
}
