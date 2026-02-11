// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {UpgradeArbOSVersionAtTimestampAction} from
    "../../../../contracts/child-chain/arbos-upgrade/UpgradeArbOSVersionAtTimestampAction.sol";

/**
 * @title DeployUpgradeArbOSVersionAtTimestampActionScript
 * @notice This script deploys UpgradeArbOSVersionAtTimestampAction
 */
contract DeployUpgradeArbOSVersionAtTimestampActionScript is Script {
    function run() public {
        uint256 arbosVersion = vm.envUint("ARBOS_VERSION");
        uint256 scheduleTimestamp = vm.envUint("SCHEDULE_TIMESTAMP");

        if (arbosVersion == 0 || scheduleTimestamp == 0) {
            revert("ARBOS_VERSION and SCHEDULE_TIMESTAMP must be set");
        }

        if (arbosVersion > type(uint64).max || scheduleTimestamp > type(uint64).max) {
            revert("ARBOS_VERSION and SCHEDULE_TIMESTAMP must be uint64");
        }

        vm.startBroadcast();

        // finally deploy upgrade action
        new UpgradeArbOSVersionAtTimestampAction({
            _newArbOSVersion: uint64(arbosVersion),
            _upgradeTimestamp: uint64(scheduleTimestamp)
        });

        vm.stopBroadcast();
    }
}
