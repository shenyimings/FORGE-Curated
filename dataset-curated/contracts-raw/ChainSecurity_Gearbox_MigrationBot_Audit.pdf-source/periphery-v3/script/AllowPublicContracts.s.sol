// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";

import {IBytecodeRepository} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";
import {Domain} from "@gearbox-protocol/permissionless/contracts/libraries/Domain.sol";

contract AllowPublicContracts is Script {
    function run() external {
        string memory csvPath = vm.envString("CSV_PATH");
        IBytecodeRepository bcr = IBytecodeRepository(vm.envAddress("BYTECODE_REPOSITORY"));

        vm.startBroadcast();
        while (true) {
            string memory line = vm.readLine(csvPath);
            if (bytes(line).length == 0) break;
            string[] memory fields = vm.split(line, ",");

            bytes32 bytecodeHash = vm.parseBytes32(fields[0]);
            bytes32 domain = Domain.extractDomain(bcr.getBytecode(bytecodeHash).contractType);
            if (bcr.isPublicDomain(domain)) bcr.allowPublicContract(bytecodeHash);
        }
        vm.stopBroadcast();
    }
}
