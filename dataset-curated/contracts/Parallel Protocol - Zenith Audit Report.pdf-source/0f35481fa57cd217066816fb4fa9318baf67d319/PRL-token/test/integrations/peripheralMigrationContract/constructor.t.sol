// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Integrations.t.sol";

contract PeripheralMigrationContract_Constructor_Integrations_Test is Integrations_Test {
    function test_PeripheralMigrationContract_Constructor() external view {
        assertEq(peripheralMigrationContractA.owner(), users.owner.addr);
        assertEq(peripheralMigrationContractA.MIMO(), mimo);
        assertEq(peripheralMigrationContractA.mainEid(), mainEid);
    }

    function test_PeripheralMigrationContract_RevertWhen_MimoAddressZero() external {
        address owner = users.owner.addr;
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.AddressZero.selector));
        new PeripheralMigrationContract(address(0), address(endpoints[mainEid]), owner, mainEid);
    }
}
