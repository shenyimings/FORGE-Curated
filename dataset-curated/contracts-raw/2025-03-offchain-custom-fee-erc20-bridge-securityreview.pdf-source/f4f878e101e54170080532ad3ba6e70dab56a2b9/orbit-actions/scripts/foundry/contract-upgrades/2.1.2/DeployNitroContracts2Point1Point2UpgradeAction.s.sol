// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {DeploymentHelpersScript} from "../../helper/DeploymentHelpers.s.sol";
import {NitroContracts2Point1Point2UpgradeAction} from
    "../../../../contracts/parent-chain/contract-upgrades/NitroContracts2Point1Point2UpgradeAction.sol";

/**
 * @title DeployNitroContracts2Point1Point2UpgradeActionScript
 * @notice This script deploys the ERC20Bridge contract and NitroContracts2Point1Point2UpgradeAction contract.
 */
contract DeployNitroContracts2Point1Point2UpgradeActionScript is DeploymentHelpersScript {
    function run() public {
        vm.startBroadcast();

        // deploy new ERC20Bridge contract from v2.1.2
        address newBridgeImpl = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.2/build/contracts/src/bridge/ERC20Bridge.sol/ERC20Bridge.json"
        );

        // deploy upgrade action
        new NitroContracts2Point1Point2UpgradeAction(newBridgeImpl);

        vm.stopBroadcast();
    }
}
