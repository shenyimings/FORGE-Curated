// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorphoBase} from "@morpho-blue/interfaces/IMorpho.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {Market, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";

// Internal imports
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract MorphoLendingAdapterRepayTest is MorphoLendingAdapterTest {
    address public alice = makeAddr("alice");

    function testFuzz_repay_RepayingLessThatWeOwe(uint64 amount) public {
        vm.assume(amount > 0);

        // Mock call so repaying shares are never bigger than borrowed shares
        vm.mockCall(
            address(morpho),
            abi.encodeWithSelector(IMorpho.market.selector),
            abi.encode(
                Market({
                    totalSupplyAssets: 0, // Not used in this test
                    totalSupplyShares: 0, // Not used in this test
                    totalBorrowAssets: 0,
                    totalBorrowShares: 1,
                    lastUpdate: 0, // Not used in this test
                    fee: 0 // Not used in this test
                })
            )
        );

        uint256 expectedRepayingShares = SharesMathLib.toSharesDown(amount, 0, 1);

        // Mock call so shares that we owe are always bigger than repaying
        vm.mockCall(
            address(morpho),
            abi.encodeWithSelector(IMorpho.position.selector),
            abi.encode(
                Position({
                    supplyShares: 0, // Not used in this test
                    borrowShares: uint128(expectedRepayingShares) + 1,
                    collateral: 0 // Not used in this test
                })
            )
        );

        // Deal alice the required debt
        deal(address(debtToken), alice, amount);

        // Alice approves the lending adapter to spend her assets
        vm.startPrank(alice);
        debtToken.approve(address(lendingAdapter), amount);

        // Expect the Alice's assets to be transferred to the lending adapter
        vm.expectCall(
            address(debtToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(lendingAdapter), amount)
        );

        // Expect the call to Morpho to accrue interest
        vm.expectCall(address(morpho), abi.encodeCall(IMorphoBase.accrueInterest, (defaultMarketParams)));

        // Expect LendingAdapter.repay to approve the morpho market to spend the assets for the amount
        vm.expectCall(address(debtToken), abi.encodeWithSelector(IERC20.approve.selector, address(morpho), amount));

        // Expect Morpho.repay to be called with the correct parameters
        vm.expectCall(
            address(morpho),
            abi.encodeCall(IMorphoBase.repay, (defaultMarketParams, amount, 0, address(lendingAdapter), hex""))
        );
        lendingAdapter.repay(amount);
        vm.stopPrank();

        assertEq(debtToken.balanceOf(address(morpho)), amount);
    }

    function testFuzz_repay_RepayingMoreThanWeOwe(uint64 amount) public {
        vm.assume(amount > 0);

        // Mock call so repaying shares are never bigger than borrowed shares
        vm.mockCall(
            address(morpho),
            abi.encodeWithSelector(IMorpho.market.selector),
            abi.encode(
                Market({
                    totalSupplyAssets: 0, // Not used in this test
                    totalSupplyShares: 0, // Not used in this test
                    totalBorrowAssets: 0,
                    totalBorrowShares: 1,
                    lastUpdate: 0, // Not used in this test
                    fee: 0 // Not used in this test
                })
            )
        );

        uint256 expectedRepayingShares = SharesMathLib.toSharesDown(amount, 0, 1);

        // Mock call so shares that we owe are always bigger than repaying
        vm.mockCall(
            address(morpho),
            abi.encodeWithSelector(IMorpho.position.selector),
            abi.encode(
                Position({
                    supplyShares: 0, // Not used in this test
                    borrowShares: uint128(expectedRepayingShares) - 1,
                    collateral: 0 // Not used in this test
                })
            )
        );

        // Deal alice the required debt
        deal(address(debtToken), alice, amount);

        // Alice approves the lending adapter to spend her assets
        vm.startPrank(alice);
        debtToken.approve(address(lendingAdapter), amount);

        // Expect the Alice's assets to be transferred to the lending adapter
        vm.expectCall(
            address(debtToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(lendingAdapter), amount)
        );

        // Expect the call to Morpho to accrue interest
        vm.expectCall(address(morpho), abi.encodeCall(IMorphoBase.accrueInterest, (defaultMarketParams)));

        // Expect LendingAdapter.repay to approve the morpho market to spend the assets for the amount
        vm.expectCall(address(debtToken), abi.encodeWithSelector(IERC20.approve.selector, address(morpho), amount));

        // Expect Morpho.repay to be called with the correct parameters
        vm.expectCall(
            address(morpho),
            abi.encodeCall(
                IMorphoBase.repay, (defaultMarketParams, 0, expectedRepayingShares - 1, address(lendingAdapter), hex"")
            )
        );
        lendingAdapter.repay(amount);
        vm.stopPrank();
    }

    function test_repay_ZeroAmount() public {
        // Nothing should happen
        lendingAdapter.repay(0);
        assertEq(debtToken.balanceOf(address(morpho)), 0);
    }
}
