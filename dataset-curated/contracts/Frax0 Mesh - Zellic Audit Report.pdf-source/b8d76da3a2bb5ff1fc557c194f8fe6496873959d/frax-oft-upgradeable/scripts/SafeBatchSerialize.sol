// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VmSafe} from "forge-std/Vm.sol";
import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct SerializedTx {
    string name;
    address to;
    uint256 value;
    bytes data;
}

contract SafeTxUtil is Script {
    using stdJson for string;

    function writeTxs(SerializedTx[] memory txs, string memory path) public {
        string memory json = "json";
        // Default values
        vm.serializeString(json, "version", "1.0");
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeUint(json, "createdAt", block.timestamp * 1000);

        string memory serializedTxs = "[";
        for (uint i = 0; i < txs.length; i++) {
            if (i != 0) {
                serializedTxs = string.concat(serializedTxs, ",");
            }

            string memory transaction = "tx";
            vm.serializeAddress(transaction, "to", txs[i].to);
            vm.serializeString(
                transaction,
                "value",
                Strings.toString(txs[i].value)
            );
            vm.serializeString(transaction, "operation", "0");
            string memory serializedTx = vm.serializeBytes(
                transaction,
                "data",
                txs[i].data
            );

            serializedTxs = string.concat(serializedTxs, serializedTx);
        }
        serializedTxs = string.concat(serializedTxs, "]");

        string memory meta = "meta";
        vm.serializeString(meta, "name", "Transactions Batch");
        string memory serializedMeta = vm.serializeString(
            meta,
            "description",
            ""
        );

        vm.serializeString(json, "transactions", serializedTxs);
        string memory finalJson = vm.serializeString(
            json,
            "meta",
            serializedMeta
        );

        vm.writeJson({json: finalJson, path: path});

        string[] memory commands = new string[](4);
        // re-used commands to find-replace
        commands[0] = "sed";
        commands[1] = "-i";
        commands[3] = path;

        // Remove all backslashes
        commands[2] = "s/\\\\//g";
        vm.ffi(commands);

        // Replace `"[` with `[`]
        commands[2] = 's/\\"\\[/\\[/g';
        vm.ffi(commands);

        // Replace `]"` with `]`
        commands[2] = 's/\\]\\"/\\]/g';
        vm.ffi(commands);
    }
}