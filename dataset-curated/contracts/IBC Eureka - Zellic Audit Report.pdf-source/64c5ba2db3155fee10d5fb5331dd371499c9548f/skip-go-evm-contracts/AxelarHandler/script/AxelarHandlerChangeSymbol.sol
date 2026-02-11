// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {AxelarHandler} from "src/AxelarHandler.sol";

contract AxelarHandlerChangeSymbolScript is Script {
    AxelarHandler public handler;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        handler = AxelarHandler(
            payable(0xf35f19BdA0cceD525E0cE1aD5f5e5666437c7664)
        );
    }

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        handler.setWETHSybol("DISABLED");
        vm.stopBroadcast();
    }
}
