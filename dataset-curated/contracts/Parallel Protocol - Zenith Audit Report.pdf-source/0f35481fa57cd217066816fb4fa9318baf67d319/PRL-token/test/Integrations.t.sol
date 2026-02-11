// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "test/Base.t.sol";

/// @notice Common logic for units tests.
abstract contract Integrations_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();

        setUpEndpoints(3, LibraryType.UltraLightNode);
        vm.startPrank(users.owner.addr);

        prl = _deployPRL(DEFAULT_PRL_SUPPLY);

        lockBox = _deployLockBox(address(prl), address(endpoints[mainEid]), users.owner.addr);

        principalMigrationContract = _deployPrincipalMigrationContract(
            address(mimo), address(prl), address(lockBox), address(endpoints[mainEid]), users.owner.addr
        );
        /// transfer the total PRL supply to the PrincipalMigrationContract
        prl.transfer(address(principalMigrationContract), DEFAULT_PRL_SUPPLY);

        peripheralMigrationContractA = _deployPeripheralMigrationContract(
            address(mimo), address(endpoints[aEid]), users.owner.addr, mainEid, "peripheralMigrationContractA"
        );

        peripheralPRLA = _deployPeripheralPRL(address(endpoints[aEid]), users.owner.addr, "peripheralPRLA");

        peripheralMigrationContractB = _deployPeripheralMigrationContract(
            address(mimo), address(endpoints[bEid]), users.owner.addr, mainEid, "peripheralMigrationContractB"
        );

        peripheralPRLB = _deployPeripheralPRL(address(endpoints[bEid]), users.owner.addr, "peripheralPRLB");

        address[] memory migrationContracts = new address[](3);
        migrationContracts[0] = address(principalMigrationContract);
        migrationContracts[1] = address(peripheralMigrationContractA);
        migrationContracts[2] = address(peripheralMigrationContractB);
        wireOApps(migrationContracts);

        address[] memory ofts = new address[](3);
        ofts[0] = address(lockBox);
        ofts[1] = address(peripheralPRLA);
        ofts[2] = address(peripheralPRLB);
        wireOApps(ofts);
    }
}
