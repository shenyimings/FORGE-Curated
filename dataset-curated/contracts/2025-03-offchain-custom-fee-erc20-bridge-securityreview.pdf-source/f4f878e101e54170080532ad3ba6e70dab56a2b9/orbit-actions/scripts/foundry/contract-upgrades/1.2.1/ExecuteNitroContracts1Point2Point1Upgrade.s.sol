// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {
    NitroContracts1Point2Point1UpgradeAction,
    ProxyAdmin
} from "../../../../contracts/parent-chain/contract-upgrades/NitroContracts1Point2Point1UpgradeAction.sol";
import {IERC20Bridge} from "@arbitrum/nitro-contracts-1.2.1/src/bridge/IERC20Bridge.sol";
import {IERC20Inbox} from "@arbitrum/nitro-contracts-1.2.1/src/bridge/IERC20Inbox.sol";
import {ISequencerInbox} from "@arbitrum/nitro-contracts-1.2.1/src/bridge/ISequencerInbox.sol";
import {IRollupCore} from "@arbitrum/nitro-contracts-1.2.1/src/rollup/IRollupCore.sol";
import {IUpgradeExecutor} from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";

import {IIsUsingFeeToken} from "../../helper/IIsUsingFeeToken.sol";

/**
 * @title ExecuteNitroContracts1Point2Point1UpgradeScript
 * @notice This script executes nitro contracts 1.2.1 upgrade through UpgradeExecutor
 */
contract ExecuteNitroContracts1Point2Point1UpgradeScript is Script {
    function run() public {
        bytes32 wasmModuleRoot = vm.envBytes32("WASM_MODULE_ROOT");
        uint256 maxDataSize = vm.envUint("MAX_DATA_SIZE");
        bool isFeeTokenChain = vm.envBool("IS_FEE_TOKEN_CHAIN");
        NitroContracts1Point2Point1UpgradeAction upgradeAction =
            NitroContracts1Point2Point1UpgradeAction(vm.envAddress("UPGRADE_ACTION_ADDRESS"));
        require(upgradeAction.newWasmModuleRoot() == wasmModuleRoot, "WASM_MODULE_ROOT mismatch");
        require(
            ISequencerInbox(upgradeAction.newSequencerInboxImpl()).maxDataSize() == maxDataSize,
            "MAX_DATA_SIZE mismatch with action"
        );
        require(
            isFeeTokenChain == IIsUsingFeeToken(upgradeAction.newSequencerInboxImpl()).isUsingFeeToken(),
            "IS_FEE_TOKEN_CHAIN mismatch with action"
        );

        IERC20Inbox inbox = IERC20Inbox(vm.envAddress("INBOX_ADDRESS"));
        address bridge = address(inbox.bridge());
        try IERC20Bridge(bridge).nativeToken() returns (address feeToken) {
            require(isFeeTokenChain || feeToken == address(0), "IS_FEE_TOKEN_CHAIN mismatch");
        } catch {
            require(!isFeeTokenChain, "IS_FEE_TOKEN_CHAIN mismatch");
        }

        try inbox.maxDataSize() returns (uint256 _maxDataSize) {
            require(_maxDataSize == maxDataSize, "MAX_DATA_SIZE mismatch with current deployment");
        } catch {
            require(maxDataSize == 117964);
        }

        vm.startBroadcast();

        // prepare upgrade calldata

        IRollupCore rollup = IRollupCore(address(IERC20Bridge(bridge).rollup()));
        ProxyAdmin proxyAdmin = ProxyAdmin(vm.envAddress("PROXY_ADMIN_ADDRESS"));
        bytes memory upgradeCalldata =
            abi.encodeCall(NitroContracts1Point2Point1UpgradeAction.perform, (rollup, proxyAdmin));

        // execute the upgrade
        IUpgradeExecutor executor = IUpgradeExecutor(vm.envAddress("PARENT_UPGRADE_EXECUTOR_ADDRESS"));
        executor.execute(address(upgradeAction), upgradeCalldata);

        // sanity check, full checks are done on-chain by the upgrade action
        require(rollup.wasmModuleRoot() == upgradeAction.newWasmModuleRoot(), "ArbOS20Action: wasm module root not set");

        vm.stopBroadcast();
    }
}
