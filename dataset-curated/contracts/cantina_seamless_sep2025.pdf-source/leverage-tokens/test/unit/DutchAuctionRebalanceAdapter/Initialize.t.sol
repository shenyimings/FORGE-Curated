// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Internal imports
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";
import {DutchAuctionRebalanceAdapterHarness} from "test/unit/harness/DutchAuctionRebalanceAdapterHarness.t.sol";

contract InitializeTest is DutchAuctionRebalanceAdapterTest {
    function test_Fuzz_Initialize(uint120 auctionDuration, uint256 initialPriceMultiplier, uint256 minPriceMultiplier)
        public
    {
        vm.assume(auctionDuration > 0);
        vm.assume(initialPriceMultiplier > minPriceMultiplier);

        address dutchAuctionRebalancerImplementation = address(new DutchAuctionRebalanceAdapterHarness());
        address dutchAuctionRebalancerProxy = UnsafeUpgrades.deployUUPSProxy(
            dutchAuctionRebalancerImplementation,
            abi.encodeWithSelector(
                DutchAuctionRebalanceAdapterHarness.initialize.selector,
                auctionDuration,
                initialPriceMultiplier,
                minPriceMultiplier
            )
        );

        DutchAuctionRebalanceAdapterHarness newDutchAuctionRebalanceAdapter =
            DutchAuctionRebalanceAdapterHarness(dutchAuctionRebalancerProxy);

        assertEq(newDutchAuctionRebalanceAdapter.getAuctionDuration(), auctionDuration);
        assertEq(newDutchAuctionRebalanceAdapter.getInitialPriceMultiplier(), initialPriceMultiplier);
        assertEq(newDutchAuctionRebalanceAdapter.getMinPriceMultiplier(), minPriceMultiplier);
    }

    function test_Fuzz_Initialize_RevertIf_InvalidAuctionDuration(
        uint256 initialPriceMultiplier,
        uint256 minPriceMultiplier
    ) public {
        vm.assume(initialPriceMultiplier > minPriceMultiplier);

        address dutchAuctionRebalancerImplementation = address(new DutchAuctionRebalanceAdapterHarness());
        vm.expectRevert(IDutchAuctionRebalanceAdapter.InvalidAuctionDuration.selector);
        UnsafeUpgrades.deployUUPSProxy(
            dutchAuctionRebalancerImplementation,
            abi.encodeWithSelector(
                DutchAuctionRebalanceAdapterHarness.initialize.selector, 0, initialPriceMultiplier, minPriceMultiplier
            )
        );
    }

    function test_Fuzz_Initialize_RevertIf_MinPriceMultiplierTooHigh(
        uint120 auctionDuration,
        uint256 initialPriceMultiplier,
        uint256 minPriceMultiplier
    ) public {
        vm.assume(minPriceMultiplier > initialPriceMultiplier);

        address dutchAuctionRebalancerImplementation = address(new DutchAuctionRebalanceAdapterHarness());

        vm.expectRevert(IDutchAuctionRebalanceAdapter.MinPriceMultiplierTooHigh.selector);
        UnsafeUpgrades.deployUUPSProxy(
            dutchAuctionRebalancerImplementation,
            abi.encodeWithSelector(
                DutchAuctionRebalanceAdapterHarness.initialize.selector,
                auctionDuration,
                initialPriceMultiplier,
                minPriceMultiplier
            )
        );
    }
}
