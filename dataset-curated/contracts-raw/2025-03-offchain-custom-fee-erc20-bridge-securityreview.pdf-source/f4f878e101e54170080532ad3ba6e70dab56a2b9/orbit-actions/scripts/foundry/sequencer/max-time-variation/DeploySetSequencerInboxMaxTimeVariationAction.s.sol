// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {SetSequencerInboxMaxTimeVariationAction} from
    "../../../../contracts/parent-chain/sequencer/SetSequencerInboxMaxTimeVariationAction.sol";

/**
 * @title DeployUpgradeArbOSVersionAtTimestampActionScript
 * @notice This script deploys UpgradeArbOSVersionAtTimestampAction
 */
contract DeploySetSequencerInboxMaxTimeVariationActionScript is Script {
    function run() public {
        vm.startBroadcast();

        // finally deploy upgrade action
        new SetSequencerInboxMaxTimeVariationAction({
            _delayBlocks: vm.envUint("DELAY_BLOCKS"),
            _futureBlocks: vm.envUint("FUTURE_BLOCKS"),
            _delaySeconds: vm.envUint("DELAY_SECONDS"),
            _futureSeconds: vm.envUint("FUTURE_SECONDS")
        });

        vm.stopBroadcast();
    }
}
