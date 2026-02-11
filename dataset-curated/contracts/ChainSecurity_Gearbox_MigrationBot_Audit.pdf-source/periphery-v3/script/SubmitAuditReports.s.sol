// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";

import {
    IBytecodeRepository,
    AuditReport
} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";

contract SubmitAuditReports is Script {
    function run() external {
        string memory csvPath = vm.envString("CSV_PATH");
        IBytecodeRepository bcr = IBytecodeRepository(vm.envAddress("BYTECODE_REPOSITORY"));

        vm.startBroadcast();
        while (true) {
            string memory line = vm.readLine(csvPath);
            if (bytes(line).length == 0) break;
            string[] memory fields = vm.split(line, ",");

            bytes32 bytecodeHash = vm.parseBytes32(fields[0]);
            AuditReport memory auditReport = AuditReport({
                auditor: vm.parseAddress(fields[1]),
                reportUrl: fields[2],
                signature: vm.parseBytes(fields[3])
            });

            bcr.submitAuditReport(bytecodeHash, auditReport);
        }
        vm.stopBroadcast();
    }
}
