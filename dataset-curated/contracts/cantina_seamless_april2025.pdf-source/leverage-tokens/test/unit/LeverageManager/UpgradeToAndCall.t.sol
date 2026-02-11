// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

// Internal imports
import {LeverageManager} from "src/LeverageManager.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";

contract UpgradeToAndCallTest is LeverageManagerTest {
    address public upgrader = makeAddr("upgrader");

    function setUp() public override {
        super.setUp();

        vm.startPrank(defaultAdmin);
        leverageManager.grantRole(leverageManager.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();
    }

    function test_upgradeToAndCall() public {
        // Deploy new implementation
        LeverageManager newImplementation = new LeverageManager();

        // Expect the Upgraded event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(address(newImplementation));

        // Upgrade
        vm.prank(upgrader);
        leverageManager.upgradeToAndCall(address(newImplementation), "");
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_upgradeToAndCall_RevertIf_NonUpgraderUpgrades(address nonUpgrader) public {
        vm.assume(nonUpgrader != upgrader);

        LeverageManager newImplementation = new LeverageManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonUpgrader, leverageManager.UPGRADER_ROLE()
            )
        );
        vm.prank(nonUpgrader);
        leverageManager.upgradeToAndCall(address(newImplementation), "");
    }
}
