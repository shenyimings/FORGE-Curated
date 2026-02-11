// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AutoCompoundBase } from "./AutoCompoundBase.t.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract AutoCompoundDelegateTest is AutoCompoundBase {
    function testRevert_NoPermission() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(acStrategy),
                address(1),
                acStrategy.AUTOCOMPOUND_STRATEGY_ADMIN_ROLE()
            )
        );
        vm.prank(address(1));
        acStrategy.delegate(address(0x123));
    }

    function test_DelegatesToAddress() public {
        address newDelegatee = address(0x123);

        acStrategy.delegate(newDelegatee);

        assertEq(acStrategy.delegatee(), newDelegatee);

        // Check delegation happened
        address actualDelegatee = ivotesAdapter.delegates(address(acStrategy));
        assertEq(actualDelegatee, newDelegatee);
    }

    function test_DelegateToZeroAddress() public {
        // First delegate to a non-zero address
        address delegatee = address(0x123);
        acStrategy.delegate(delegatee);
        assertEq(acStrategy.delegatee(), delegatee);

        // Then delegate to zero address
        acStrategy.delegate(address(0));
        assertEq(acStrategy.delegatee(), address(0));
    }
}
