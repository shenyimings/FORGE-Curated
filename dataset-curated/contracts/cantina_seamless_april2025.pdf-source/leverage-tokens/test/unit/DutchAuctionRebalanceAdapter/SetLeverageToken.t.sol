// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

import {DutchAuctionRebalanceAdapterHarness} from "test/unit/harness/DutchAuctionRebalanceAdapterHarness.t.sol";
import {DutchAuctionRebalanceAdapterTest} from "./DutchAuctionRebalanceAdapter.t.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";

contract SetLeverageTokenTest is Test {
    DutchAuctionRebalanceAdapterHarness public rebalanceAdapter;

    function setUp() public {
        address dutchAuctionRebalancerImplementation = address(new DutchAuctionRebalanceAdapterHarness());
        address dutchAuctionRebalancerProxy = UnsafeUpgrades.deployUUPSProxy(
            dutchAuctionRebalancerImplementation,
            abi.encodeWithSelector(DutchAuctionRebalanceAdapterHarness.initialize.selector, 1, 1, 1)
        );
        rebalanceAdapter = DutchAuctionRebalanceAdapterHarness(address(dutchAuctionRebalancerProxy));
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setLeverageToken(ILeverageToken token) public {
        rebalanceAdapter.exposed_setLeverageToken(token);

        assertEq(address(rebalanceAdapter.getLeverageToken()), address(token));
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setLeverageToken_RevertIf_LeverageTokenAlreadySet(ILeverageToken token1, ILeverageToken token2)
        public
    {
        vm.assume(address(token1) != address(0));
        rebalanceAdapter.exposed_setLeverageToken(token1);

        vm.expectRevert(abi.encodeWithSelector(IDutchAuctionRebalanceAdapter.LeverageTokenAlreadySet.selector));
        rebalanceAdapter.exposed_setLeverageToken(token2);
    }
}
