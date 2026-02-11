// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {
    NitroContracts2Point1Point3UpgradeAction,
    ProxyAdmin
} from "../../../../contracts/parent-chain/contract-upgrades/NitroContracts2Point1Point3UpgradeAction.sol";
import {IInboxBase} from "@arbitrum/nitro-contracts-1.2.1/src/bridge/IInboxBase.sol";
import {IERC20Bridge} from "@arbitrum/nitro-contracts-2.1.2/src/bridge/IERC20Bridge.sol";
import {IUpgradeExecutor} from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";

/**
 * @title ExecuteNitroContracts1Point2Point3UpgradeScript
 * @notice This script executes nitro contracts 2.1.3 upgrade through UpgradeExecutor
 */
contract ExecuteNitroContracts2Point1Point3UpgradeScript is Script {
    function run() public {
        NitroContracts2Point1Point3UpgradeAction upgradeAction =
            NitroContracts2Point1Point3UpgradeAction(vm.envAddress("UPGRADE_ACTION_ADDRESS"));

        address inbox = (vm.envAddress("INBOX_ADDRESS"));

        // prepare upgrade calldata
        ProxyAdmin proxyAdmin = ProxyAdmin(vm.envAddress("PROXY_ADMIN_ADDRESS"));
        bytes memory upgradeCalldata =
            abi.encodeCall(NitroContracts2Point1Point3UpgradeAction.perform, (inbox, proxyAdmin));

        // execute the upgrade
        // action checks prerequisites, and script will fail if the action reverts
        IUpgradeExecutor executor = IUpgradeExecutor(vm.envAddress("PARENT_UPGRADE_EXECUTOR_ADDRESS"));
        vm.startBroadcast();
        executor.execute(address(upgradeAction), upgradeCalldata);
        vm.stopBroadcast();
    }
}
