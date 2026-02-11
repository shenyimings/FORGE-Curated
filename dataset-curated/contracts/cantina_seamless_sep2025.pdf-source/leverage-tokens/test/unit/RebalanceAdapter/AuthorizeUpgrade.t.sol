// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {RebalanceAdapterTest} from "./RebalanceAdapter.t.sol";

contract AuthorizeUpgradeTest is RebalanceAdapterTest {
    function testFuzz_authorizeUpgrade(address caller, address newImplementation) public {
        vm.assume(caller != rebalanceAdapter.owner());
        vm.assume(caller != address(0));

        vm.prank(rebalanceAdapter.owner());
        rebalanceAdapter.transferOwnership(caller);

        vm.prank(rebalanceAdapter.owner());
        rebalanceAdapter.exposed_authorizeUpgrade(newImplementation);
    }

    function testFuzz_authorizeUpgrade_RevertIf_CallerIsNotUpgrader(address caller, address newImplementation) public {
        vm.assume(caller != rebalanceAdapter.owner());

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        rebalanceAdapter.exposed_authorizeUpgrade(newImplementation);
    }
}
