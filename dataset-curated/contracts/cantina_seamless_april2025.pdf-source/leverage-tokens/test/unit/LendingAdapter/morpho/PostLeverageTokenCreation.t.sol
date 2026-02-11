// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";

contract PostLeverageTokenCreation is MorphoLendingAdapterTest {
    // forge-config: default.fuzz.runs = 1
    function testFuzz_postLeverageTokenCreation(address creator, address token) public {
        lendingAdapter = new MorphoLendingAdapter(leverageManager, IMorpho(address(morpho)));
        MorphoLendingAdapter(address(lendingAdapter)).initialize(defaultMarketId, creator);

        vm.prank(address(leverageManager));
        vm.expectEmit(true, true, true, true);
        emit IMorphoLendingAdapter.MorphoLendingAdapterUsed();
        lendingAdapter.postLeverageTokenCreation(creator, token); // Should not revert
    }

    // forge-config: default.fuzz.runs = 1
    function testFuzz_postLeverageTokenCreation_RevertIf_CreatorIsNotAuthorized(address creator, address token)
        public
    {
        vm.assume(creator != authorizedCreator);

        vm.expectRevert(abi.encodeWithSelector(ILendingAdapter.Unauthorized.selector));
        vm.prank(address(leverageManager));
        lendingAdapter.postLeverageTokenCreation(creator, token);
    }

    // forge-config: default.fuzz.runs = 1
    function testFuzz_postLeverageTokenCreation_RevertIf_CallerIsNotLeverageManager(address caller, address token)
        public
    {
        vm.assume(caller != address(leverageManager));

        vm.expectRevert(abi.encodeWithSelector(ILendingAdapter.Unauthorized.selector));
        vm.prank(caller);
        lendingAdapter.postLeverageTokenCreation(authorizedCreator, token);
    }

    // forge-config: default.fuzz.runs = 1
    function test_postLeverageTokenCreation_RevertIf_LendingAdapterIsAlreadyUsed(address token) public {
        vm.prank(address(leverageManager));
        lendingAdapter.postLeverageTokenCreation(authorizedCreator, token);

        vm.expectRevert(abi.encodeWithSelector(IMorphoLendingAdapter.LendingAdapterAlreadyInUse.selector));
        vm.prank(address(leverageManager));
        lendingAdapter.postLeverageTokenCreation(authorizedCreator, token);
    }
}
