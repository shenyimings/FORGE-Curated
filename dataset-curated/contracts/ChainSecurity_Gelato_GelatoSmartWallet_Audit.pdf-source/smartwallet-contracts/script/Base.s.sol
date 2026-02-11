// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    address internal broadcaster;

    uint256 private privateKey;

    bytes32 internal constant GELATO_SALT = bytes32(keccak256("gelato.deployer"));

    constructor() {
        privateKey = vm.envUint("PRIVATE_KEY");
        broadcaster = vm.rememberKey(privateKey);
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }
}
