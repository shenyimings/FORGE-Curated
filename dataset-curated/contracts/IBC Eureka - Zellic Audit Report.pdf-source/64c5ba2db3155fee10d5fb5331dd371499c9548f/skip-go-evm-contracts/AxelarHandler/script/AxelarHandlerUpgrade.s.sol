// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {AxelarHandler} from "src/AxelarHandler.sol";

contract AxelarHandlerUpgradeScript is Script {
    AxelarHandler public handler;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        handler = AxelarHandler(
            payable(0xD397883c12b71ea39e0d9f6755030205f31A1c96)
        );
    }

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        AxelarHandler newImplementation = new AxelarHandler();
        handler.upgradeTo(address(newImplementation));
        vm.stopBroadcast();
    }
}
