// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { BaseTest } from "@test/base/BaseTest.sol";

contract TrustedFillerRegistryTest is BaseTest {
    function test_onlyAllowTrustedFillers() public {
        vm.expectRevert();
        trustedFillerRegistry.createTrustedFiller(address(this), address(123), bytes32(0));

        // This is allowed
        trustedFillerRegistry.createTrustedFiller(address(this), address(cowSwapFiller), bytes32(0));
    }
}
