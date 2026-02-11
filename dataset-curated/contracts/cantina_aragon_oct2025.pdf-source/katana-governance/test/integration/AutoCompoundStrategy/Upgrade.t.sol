// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AutoCompoundBase } from "./AutoCompoundBase.t.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract AutoCompoundUpgradeTest is AutoCompoundBase {
    function testRevert_Unauthorized() public {
        address newImplementation = address(new AutoCompoundStrategy());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(acStrategy),
                address(alice),
                acStrategy.AUTOCOMPOUND_STRATEGY_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        acStrategy.upgradeTo(newImplementation);
    }

    function test_Authorized() public {
        address newImplementation = address(new AutoCompoundStrategy());

        // Upgrade should succeed
        acStrategy.upgradeTo(address(newImplementation));

        assertEq(acStrategy.implementation(), address(newImplementation));
    }
}
