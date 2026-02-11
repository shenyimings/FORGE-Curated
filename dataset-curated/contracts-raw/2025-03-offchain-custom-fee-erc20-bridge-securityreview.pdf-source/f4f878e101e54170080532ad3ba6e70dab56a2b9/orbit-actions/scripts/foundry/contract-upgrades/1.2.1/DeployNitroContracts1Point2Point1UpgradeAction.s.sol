// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import {IReader4844} from "@arbitrum/nitro-contracts-1.2.1/src/libraries/IReader4844.sol";
import {NitroContracts1Point2Point1UpgradeAction} from
    "../../../../contracts/parent-chain/contract-upgrades/NitroContracts1Point2Point1UpgradeAction.sol";

import {ArbitrumChecker} from "@arbitrum/nitro-contracts-1.2.1/src/libraries/ArbitrumChecker.sol";
import {MockArbSys} from "../../helper/MockArbSys.sol";

/**
 * @title DeployNitroContracts1Point2Point1UpgradeActionScript
 * @notice This script deploys OSPs and ChallengeManager templates, blob reader and SequencerInbox template.
 *          Not applicable for Arbitrum based chains due to precompile call in SequencerInbox (Foundry simulation breaks).
 */
contract DeployNitroContracts1Point2Point1UpgradeActionScript is Script {
    function run() public {
        bool isArbitrum = vm.envBool("PARENT_CHAIN_IS_ARBITRUM");
        if (isArbitrum) {
            // etch a mock ArbSys contract so that foundry simulate it nicely
            bytes memory mockArbSysCode = address(new MockArbSys()).code;
            vm.etch(address(100), mockArbSysCode);
        }

        vm.startBroadcast();

        // deploy OSP templates
        address osp0 = _deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/osp/OneStepProver0.sol/OneStepProver0.json"
        );
        address ospMemory = _deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/osp/OneStepProverMemory.sol/OneStepProverMemory.json"
        );
        address ospMath = _deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/osp/OneStepProverMath.sol/OneStepProverMath.json"
        );
        address ospHostIo = _deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/osp/OneStepProverHostIo.sol/OneStepProverHostIo.json"
        );
        address osp = _deployBytecodeWithConstructorFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/osp/OneStepProofEntry.sol/OneStepProofEntry.json",
            abi.encode(osp0, ospMemory, ospMath, ospHostIo)
        );

        // deploy new challenge manager templates
        address challengeManager = _deployBytecodeFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/challenge/ChallengeManager.sol/ChallengeManager.json"
        );

        address reader4844Address;
        if (!isArbitrum) {
            // deploy blob reader
            reader4844Address = _deployBytecodeFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.2.1/out/yul/Reader4844.yul/Reader4844.json"
            );
        }

        if (vm.envOr("DEPLOY_BOTH", false)) {
            // if true, also deploy the !IS_FEE_TOKEN_CHAIN action
            // only used to save gas cost when deploying both native and custom fee version

            // deploy sequencer inbox template
            address seqInbox2 = _deployBytecodeWithConstructorFromJSON(
                "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/bridge/SequencerInbox.sol/SequencerInbox.json",
                abi.encode(vm.envUint("MAX_DATA_SIZE"), reader4844Address, !vm.envBool("IS_FEE_TOKEN_CHAIN"))
            );

            // finally deploy upgrade action
            new NitroContracts1Point2Point1UpgradeAction({
                _newWasmModuleRoot: vm.envBytes32("WASM_MODULE_ROOT"),
                _newSequencerInboxImpl: seqInbox2,
                _newChallengeMangerImpl: challengeManager,
                _newOsp: osp
            });
        }

        // deploy sequencer inbox template
        address seqInbox = _deployBytecodeWithConstructorFromJSON(
            "/node_modules/@arbitrum/nitro-contracts-1.2.1/build/contracts/src/bridge/SequencerInbox.sol/SequencerInbox.json",
            abi.encode(vm.envUint("MAX_DATA_SIZE"), reader4844Address, vm.envBool("IS_FEE_TOKEN_CHAIN"))
        );

        // finally deploy upgrade action
        new NitroContracts1Point2Point1UpgradeAction({
            _newWasmModuleRoot: vm.envBytes32("WASM_MODULE_ROOT"),
            _newSequencerInboxImpl: seqInbox,
            _newChallengeMangerImpl: challengeManager,
            _newOsp: osp
        });

        vm.stopBroadcast();
    }

    function _deployBytecode(bytes memory bytecode) internal returns (address) {
        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "bytecode deployment failed");
        return addr;
    }

    function _deployBytecodeWithConstructor(bytes memory bytecode, bytes memory abiencodedargs)
        internal
        returns (address)
    {
        bytes memory bytecodeWithConstructor = bytes.concat(bytecode, abiencodedargs);
        return _deployBytecode(bytecodeWithConstructor);
    }

    /**
     * @notice Read bytecode from JSON file at path
     */
    function _getBytecode(bytes memory path) internal view returns (bytes memory) {
        string memory readerBytecodeFilePath = string(abi.encodePacked(vm.projectRoot(), path));
        string memory json = vm.readFile(readerBytecodeFilePath);
        try vm.parseJsonBytes(json, ".bytecode.object") returns (bytes memory bytecode) {
            return bytecode;
        } catch {
            return vm.parseJsonBytes(json, ".bytecode");
        }
    }

    function _deployBytecodeFromJSON(bytes memory path) internal returns (address) {
        bytes memory bytecode = _getBytecode(path);
        return _deployBytecode(bytecode);
    }

    function _deployBytecodeWithConstructorFromJSON(bytes memory path, bytes memory abiencodedargs)
        internal
        returns (address)
    {
        bytes memory bytecode = _getBytecode(path);
        return _deployBytecodeWithConstructor(bytecode, abiencodedargs);
    }
}
