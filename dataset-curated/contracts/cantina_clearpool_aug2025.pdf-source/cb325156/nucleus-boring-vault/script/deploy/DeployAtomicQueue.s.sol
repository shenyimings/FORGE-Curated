// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { AtomicQueue } from "./../../src/atomic-queue/AtomicQueue.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { ConfigReader } from "../ConfigReader.s.sol";

using StdJson for string;

bytes32 constant SALT = 0x5bac910c72debe007de11e000000000000000000000000000000000000000000;

contract DeployAtomicQueue is BaseScript {
    function run() public broadcast returns (AtomicQueue atomicQueue) {
        // Need to pass config to get accountant
        ConfigReader.Config memory config = getConfig();

        bytes memory creationCode = abi.encodePacked(type(AtomicQueue).creationCode, abi.encode(config.accountant));

        atomicQueue = AtomicQueue(CREATEX.deployCreate3(SALT, creationCode));
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        bytes memory creationCode = abi.encodePacked(type(AtomicQueue).creationCode, abi.encode(config.accountant));

        return CREATEX.deployCreate3(SALT, creationCode);
    }
}
