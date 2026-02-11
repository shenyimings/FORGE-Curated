// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {DeploymentHelpersScript} from "../../helper/DeploymentHelpers.s.sol";
import {NitroContracts2Point1Point3UpgradeAction} from
    "../../../../contracts/parent-chain/contract-upgrades/NitroContracts2Point1Point3UpgradeAction.sol";

/**
 * @title DeployNitroContracts2Point1Point2UpgradeActionScript
 * @notice This script deploys the ERC20Bridge contract and NitroContracts2Point1Point2UpgradeAction contract.
 */
contract DeployNitroContracts2Point1Point3UpgradeActionScript is DeploymentHelpersScript {
    function run() public {
        vm.startBroadcast();

        // deploy new ERC20Inbox contract from v2.1.3
        address newEthInboxImpl = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.3/build/contracts/src/bridge/Inbox.sol/Inbox.json"
        );
        // deploy new ERC20Inbox contract from v2.1.3
        address newERC20InboxImpl = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.3/build/contracts/src/bridge/ERC20Inbox.sol/ERC20Inbox.json"
        );
        // deploy new ERC20Inbox contract from v2.1.3
        address newSeqInboxImpl = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.3/build/contracts/src/bridge/SequencerInbox.sol/SequencerInbox.json"
        );

        // deploy upgrade action
        new NitroContracts2Point1Point3UpgradeAction(newEthInboxImpl, newERC20InboxImpl, newSeqInboxImpl);

        vm.stopBroadcast();
    }
}
