// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {AxelarHandler} from "src/AxelarHandler.sol";

contract AxelarHandlerSetRouterScript is Script {
    AxelarHandler public handler;
    address public router;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        handler = AxelarHandler(payable(0xD397883c12b71ea39e0d9f6755030205f31A1c96));
        router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    }

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        handler.setSwapRouter(router);
        vm.stopBroadcast();
    }
}
