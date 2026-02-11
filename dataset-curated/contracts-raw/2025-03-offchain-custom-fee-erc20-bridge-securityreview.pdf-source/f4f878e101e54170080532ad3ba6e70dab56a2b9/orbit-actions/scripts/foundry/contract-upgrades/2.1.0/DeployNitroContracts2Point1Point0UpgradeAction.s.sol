// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {DeploymentHelpersScript} from "../../helper/DeploymentHelpers.s.sol";
import {
    NitroContracts2Point1Point0UpgradeAction,
    IOneStepProofEntry
} from "../../../../contracts/parent-chain/contract-upgrades/NitroContracts2Point1Point0UpgradeAction.sol";
import {MockArbSys} from "../../helper/MockArbSys.sol";

/**
 * @title DeployNitroContracts2Point1Point0UpgradeActionScript
 * @notice This script deploys OSPs, ChallengeManager and Rollup templates, and the upgrade action.
 */
contract DeployNitroContracts2Point1Point0UpgradeActionScript is DeploymentHelpersScript {
    // ArbOS v32 https://github.com/OffchainLabs/nitro/releases/tag/consensus-v32
    bytes32 public constant WASM_MODULE_ROOT = 0x184884e1eb9fefdc158f6c8ac912bb183bf3cf83f0090317e0bc4ac5860baa39;

    // ArbOS v20 https://github.com/OffchainLabs/nitro/releases/tag/consensus-v20
    bytes32 public constant COND_WASM_MODULE_ROOT = 0x8b104a2e80ac6165dc58b9048de12f301d70b02a0ab51396c22b4b4b802a16a4;

    function run() public {
        bool isArbitrum = vm.envBool("PARENT_CHAIN_IS_ARBITRUM");
        if (isArbitrum) {
            // etch a mock ArbSys contract so that foundry simulate it nicely
            bytes memory mockArbSysCode = address(new MockArbSys()).code;
            vm.etch(address(100), mockArbSysCode);
        }

        vm.startBroadcast();

        // deploy new osp from v2.1.0
        address newOsp;
        {
            address osp0 = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/osp/OneStepProver0.sol/OneStepProver0.json"
            );
            address ospMemory = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/osp/OneStepProverMemory.sol/OneStepProverMemory.json"
            );
            address ospMath = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/osp/OneStepProverMath.sol/OneStepProverMath.json"
            );
            address ospHostIo = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/osp/OneStepProverHostIo.sol/OneStepProverHostIo.json"
            );
            newOsp = deployBytecodeWithConstructorFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/osp/OneStepProofEntry.sol/OneStepProofEntry.json",
                abi.encode(osp0, ospMemory, ospMath, ospHostIo)
            );
        }

        // deploy condOsp from v1.3.0
        address condOsp;
        {
            address osp0 = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.3.0/build/contracts/src/osp/OneStepProver0.sol/OneStepProver0.json"
            );
            address ospMemory = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.3.0/build/contracts/src/osp/OneStepProverMemory.sol/OneStepProverMemory.json"
            );
            address ospMath = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.3.0/build/contracts/src/osp/OneStepProverMath.sol/OneStepProverMath.json"
            );
            address ospHostIo = deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.3.0/build/contracts/src/osp/OneStepProverHostIo.sol/OneStepProverHostIo.json"
            );
            condOsp = deployBytecodeWithConstructorFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.3.0/build/contracts/src/osp/OneStepProofEntry.sol/OneStepProofEntry.json",
                abi.encode(osp0, ospMemory, ospMath, ospHostIo)
            );
        }

        // deploy new challenge manager from v2.1.0
        address challengeManager = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/challenge/ChallengeManager.sol/ChallengeManager.json"
        );

        // deploy new RollupAdminLogic contract from v2.1.0
        address newRollupAdminLogic = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/rollup/RollupAdminLogic.sol/RollupAdminLogic.json"
        );

        // deploy new RollupUserLogic contract from v2.1.0
        address newRollupUserLogic = deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-2.1.0/build/contracts/src/rollup/RollupUserLogic.sol/RollupUserLogic.json"
        );

        // finally deploy upgrade action
        new NitroContracts2Point1Point0UpgradeAction({
            _newWasmModuleRoot: WASM_MODULE_ROOT,
            _newChallengeManagerImpl: challengeManager,
            _osp: IOneStepProofEntry(newOsp),
            _condRoot: COND_WASM_MODULE_ROOT,
            _condOsp: IOneStepProofEntry(condOsp),
            _newRollupAdminLogic: newRollupAdminLogic,
            _newRollupUserLogic: newRollupUserLogic
        });

        vm.stopBroadcast();
    }
}
