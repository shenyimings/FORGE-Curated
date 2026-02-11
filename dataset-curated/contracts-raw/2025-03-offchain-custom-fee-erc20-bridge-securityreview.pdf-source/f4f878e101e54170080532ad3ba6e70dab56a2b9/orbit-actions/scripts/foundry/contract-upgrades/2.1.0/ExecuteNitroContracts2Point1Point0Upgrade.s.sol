// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {
    NitroContracts2Point1Point0UpgradeAction,
    ProxyAdmin
} from "../../../../contracts/parent-chain/contract-upgrades/NitroContracts2Point1Point0UpgradeAction.sol";
import {IBridge} from "@arbitrum/nitro-contracts-2.1.0/src/bridge/IBridge.sol";
import {IRollupCore} from "@arbitrum/nitro-contracts-2.1.0/src/rollup/IRollupCore.sol";
import {IUpgradeExecutor} from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import {IInboxBase} from "@arbitrum/nitro-contracts-1.2.1/src/bridge/IInboxBase.sol";

/**
 * @title ExecuteNitroContracts1Point2Point1UpgradeScript
 * @notice This script executes nitro contracts 2.1.0 upgrade through UpgradeExecutor
 */
contract ExecuteNitroContracts2Point1Point0UpgradeScript is Script {
    function run() public {
        // used to check upgrade was successful
        bytes32 wasmModuleRoot = vm.envBytes32("TARGET_WASM_MODULE_ROOT");

        NitroContracts2Point1Point0UpgradeAction upgradeAction =
            NitroContracts2Point1Point0UpgradeAction(vm.envAddress("UPGRADE_ACTION_ADDRESS"));

        IInboxBase inbox = IInboxBase(vm.envAddress("INBOX_ADDRESS"));

        // check prerequisites
        IRollupCore rollup = IRollupCore(address(inbox.bridge().rollup()));
        require(rollup.wasmModuleRoot() == upgradeAction.condRoot(), "Incorrect starting wasm module root");

        vm.startBroadcast();

        // prepare upgrade calldata
        ProxyAdmin proxyAdmin = ProxyAdmin(vm.envAddress("PROXY_ADMIN_ADDRESS"));
        bytes memory upgradeCalldata =
            abi.encodeCall(NitroContracts2Point1Point0UpgradeAction.perform, (rollup, proxyAdmin));

        // execute the upgrade
        IUpgradeExecutor executor = IUpgradeExecutor(vm.envAddress("PARENT_UPGRADE_EXECUTOR_ADDRESS"));
        executor.execute(address(upgradeAction), upgradeCalldata);

        // sanity check, full checks are done on-chain by the upgrade action
        require(rollup.wasmModuleRoot() == upgradeAction.newWasmModuleRoot(), "Wasm module root not set");
        require(rollup.wasmModuleRoot() == wasmModuleRoot, "Unexpected wasm module root set");

        vm.stopBroadcast();
    }
}
