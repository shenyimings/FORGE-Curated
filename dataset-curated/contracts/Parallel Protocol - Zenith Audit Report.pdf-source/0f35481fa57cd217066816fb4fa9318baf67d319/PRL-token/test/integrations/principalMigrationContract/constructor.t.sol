// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract PrincipalMigrationContract_Constructor_Integrations_Test is Integrations_Test {
    function test_PrincipalMigrationContract_Constructor() external view {
        assertEq(principalMigrationContract.owner(), users.owner.addr);
        assertEq(principalMigrationContract.MIMO(), mimo);
        assertEq(principalMigrationContract.PRL(), prl);
        assertEq(address(principalMigrationContract.lockBox()), address(lockBox));
    }

    function test_PrincipalMigrationContract_RevertWhen_MimoAddressZero() external {
        address owner = users.owner.addr;
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AddressZero.selector));
        new PrincipalMigrationContract(address(0), address(prl), address(lockBox), address(endpoints[mainEid]), owner);
    }

    function test_PrincipalMigrationContract_RevertWhen_PRLAddressZero() external {
        address owner = users.owner.addr;
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AddressZero.selector));
        new PrincipalMigrationContract(address(mimo), address(0), address(lockBox), address(endpoints[mainEid]), owner);
    }

    function test_PrincipalMigrationContract_RevertWhen_LockBoxAddressZero() external {
        address owner = users.owner.addr;
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AddressZero.selector));
        new PrincipalMigrationContract(address(mimo), address(prl), address(0), address(endpoints[mainEid]), owner);
    }
}
