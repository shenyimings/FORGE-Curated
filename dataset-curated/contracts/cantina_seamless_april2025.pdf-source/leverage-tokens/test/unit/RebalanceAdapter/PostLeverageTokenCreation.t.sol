// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

// Internal imports
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";

contract PostLeverageTokenCreation is Test {
    ILeverageManager public leverageManager = ILeverageManager(makeAddr("leverageManager"));
    address public authorizedCreator = makeAddr("authorizedCreator");

    RebalanceAdapter public rebalanceAdapter;

    function setUp() public {
        rebalanceAdapter = new RebalanceAdapter();
        rebalanceAdapter.initialize(
            RebalanceAdapter.RebalanceAdapterInitParams({
                owner: address(this),
                authorizedCreator: authorizedCreator,
                leverageManager: leverageManager,
                minCollateralRatio: 1e18,
                targetCollateralRatio: 2e18,
                maxCollateralRatio: 3e18,
                auctionDuration: 1 days,
                initialPriceMultiplier: 1.1e18,
                minPriceMultiplier: 0.1e18,
                preLiquidationCollateralRatioThreshold: 1.1e18,
                rebalanceReward: 0.1e18
            })
        );
    }

    // forge-config: default.fuzz.runs = 1
    function testFuzz_postLeverageTokenCreation(address token) public {
        vm.prank(address(leverageManager));
        rebalanceAdapter.postLeverageTokenCreation(authorizedCreator, token); // Should not revert

        assertEq(address(rebalanceAdapter.getLeverageToken()), token);
    }

    // forge-config: default.fuzz.runs = 1
    function testFuzz_postLeverageTokenCreation_RevertIf_CreatorIsNotAuthorized(address creator, address token)
        public
    {
        vm.assume(creator != authorizedCreator);

        vm.expectRevert(abi.encodeWithSelector(IRebalanceAdapter.Unauthorized.selector));
        vm.prank(address(leverageManager));
        rebalanceAdapter.postLeverageTokenCreation(creator, token);
    }

    // forge-config: default.fuzz.runs = 1
    function testFuzz_postLeverageTokenCreation_RevertIf_CallerIsNotLeverageManager(address caller, address token)
        public
    {
        vm.assume(caller != address(leverageManager));

        vm.expectRevert(abi.encodeWithSelector(IRebalanceAdapter.Unauthorized.selector));
        vm.prank(caller);
        rebalanceAdapter.postLeverageTokenCreation(authorizedCreator, token);
    }

    // forge-config: default.fuzz.runs = 1
    function test_postLeverageTokenCreation_RevertIf_LeverageTokenAlreadySet(address token) public {
        vm.assume(token != address(0));
        vm.prank(address(leverageManager));
        rebalanceAdapter.postLeverageTokenCreation(authorizedCreator, token);

        vm.expectRevert(abi.encodeWithSelector(IDutchAuctionRebalanceAdapter.LeverageTokenAlreadySet.selector));
        vm.prank(address(leverageManager));
        rebalanceAdapter.postLeverageTokenCreation(authorizedCreator, token);
    }
}
