// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";

contract UpgradeTest is DutchAuctionTest {
    function testFork_Upgrade() public {
        RebalanceAdapter newImplementation = new RebalanceAdapter();
        ethLong2xRebalanceAdapter.upgradeToAndCall(address(newImplementation), "");

        assertEq(address(ethLong2xRebalanceAdapter.getLeverageToken()), address(ethLong2x));
        assertEq(address(ethLong2xRebalanceAdapter.getLeverageManager()), address(leverageManager));
        assertEq(ethLong2xRebalanceAdapter.getAuctionDuration(), 7 minutes);
        assertEq(ethLong2xRebalanceAdapter.getInitialPriceMultiplier(), 1.2e18);
        assertEq(ethLong2xRebalanceAdapter.getMinPriceMultiplier(), 0.98e18);
        assertEq(ethLong2xRebalanceAdapter.getLeverageTokenMinCollateralRatio(), 1.8e18);
        assertEq(ethLong2xRebalanceAdapter.getLeverageTokenMaxCollateralRatio(), 2.2e18);
    }

    function testFork_Upgrade_RevertIf_NonOwner() public {
        address nonOwner = makeAddr("nonOwner");

        RebalanceAdapter newImplementation = new RebalanceAdapter();
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));

        vm.prank(nonOwner);
        ethLong2xRebalanceAdapter.upgradeToAndCall(address(newImplementation), "");
    }
}
