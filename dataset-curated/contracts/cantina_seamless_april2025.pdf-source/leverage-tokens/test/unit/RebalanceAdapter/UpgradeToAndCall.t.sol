// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {RebalanceAdapterTest} from "./RebalanceAdapter.t.sol";
import {RebalanceAdapterHarness} from "test/unit/harness/RebalaneAdapterHarness.t.sol";

contract UpgradeToAndCallTest is RebalanceAdapterTest {
    function test_upgradeToAndCall() public {
        address newImplementation = address(new RebalanceAdapterHarness());

        vm.prank(rebalanceAdapter.owner());
        rebalanceAdapter.upgradeToAndCall(newImplementation, "");
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_upgradeToAndCall_RevertIf_NonOwner(address nonUpgrader, address newImplementation) public {
        vm.assume(nonUpgrader != rebalanceAdapter.owner());

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonUpgrader));
        vm.prank(nonUpgrader);
        rebalanceAdapter.upgradeToAndCall(newImplementation, "");
    }
}
