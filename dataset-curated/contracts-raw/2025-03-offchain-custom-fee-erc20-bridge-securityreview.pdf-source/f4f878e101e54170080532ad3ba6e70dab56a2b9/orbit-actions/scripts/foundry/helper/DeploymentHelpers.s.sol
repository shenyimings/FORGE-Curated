// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";

/**
 * @title DeploymentHelpersScript
 * @notice Collection of deployment helper functions
 */
contract DeploymentHelpersScript is Script {
    function deployBytecode(bytes memory bytecode) public returns (address) {
        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "bytecode deployment failed");
        return addr;
    }

    function deployBytecodeWithConstructor(bytes memory bytecode, bytes memory abiencodedargs)
        public
        returns (address)
    {
        bytes memory bytecodeWithConstructor = bytes.concat(bytecode, abiencodedargs);
        return deployBytecode(bytecodeWithConstructor);
    }

    /**
     * @notice Read bytecode from JSON file at path
     */
    function getBytecode(bytes memory path) public view returns (bytes memory) {
        string memory readerBytecodeFilePath = string(abi.encodePacked(vm.projectRoot(), path));
        string memory json = vm.readFile(readerBytecodeFilePath);
        try vm.parseJsonBytes(json, ".bytecode.object") returns (bytes memory bytecode) {
            return bytecode;
        } catch {
            return vm.parseJsonBytes(json, ".bytecode");
        }
    }

    function deployBytecodeFromJSON(bytes memory path) public returns (address) {
        bytes memory bytecode = getBytecode(path);
        return deployBytecode(bytecode);
    }

    function deployBytecodeWithConstructorFromJSON(bytes memory path, bytes memory abiencodedargs)
        public
        returns (address)
    {
        bytes memory bytecode = getBytecode(path);
        return deployBytecodeWithConstructor(bytecode, abiencodedargs);
    }
}
