// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../../Base.sol";

import { DaoUnauthorized } from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import { AvKATVault } from "src/AvKATVault.sol";

contract VaultUpgradeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function testRevert_UpgradeUnauthorized() public {
        address newImplementation = address(new AvKATVault());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(vault),
                address(alice),
                AvKATVault(newImplementation).VAULT_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        vault.upgradeTo(newImplementation);
    }

    function test_UpgradeAuthorized() public {
        address newImplementation = address(new AvKATVault());

        // Upgrade should succeed
        vault.upgradeTo(address(newImplementation));

        assertEq(vault.implementation(), address(newImplementation));
    }
}
