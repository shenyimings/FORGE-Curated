// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { MockRoleRegistry } from "@mock/MockRoleRegistry.sol";
import { TrustedFillerRegistry, IRoleRegistry } from "@src/TrustedFillerRegistry.sol";

import { CowSwapFiller } from "@src/fillers/cowswap/CowSwapFiller.sol";

abstract contract BaseTest is Test {
    IRoleRegistry public roleRegistry;
    TrustedFillerRegistry public trustedFillerRegistry;

    CowSwapFiller public cowSwapFiller;

    function setUp() public {
        roleRegistry = new MockRoleRegistry();
        trustedFillerRegistry = new TrustedFillerRegistry(address(roleRegistry));

        cowSwapFiller = new CowSwapFiller();

        trustedFillerRegistry.addTrustedFiller(cowSwapFiller);

        _setUp();
    }

    /// @dev Implement this if you want a custom configured deployment
    function _setUp() public virtual {}
}
