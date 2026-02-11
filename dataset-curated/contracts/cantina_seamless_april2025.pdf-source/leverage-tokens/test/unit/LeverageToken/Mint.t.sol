// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Internal imports
import {LeverageTokenTest} from "./LeverageToken.t.sol";
import {LeverageToken} from "src/LeverageToken.sol";

contract MintTest is LeverageTokenTest {
    /// forge-config: default.fuzz.runs = 1
    function test_mint(address to, uint256 amount) public {
        vm.assume(to != address(0));

        leverageToken.mint(to, amount);
        assertEq(leverageToken.balanceOf(to), amount);
    }

    /// forge-config: default.fuzz.runs = 1
    function test_mint_RevertIf_CallerIsNotOwner(address caller, address to, uint256 amount) public {
        vm.assume(caller != address(0));

        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        leverageToken.mint(to, amount);
        vm.stopPrank();
    }
}
