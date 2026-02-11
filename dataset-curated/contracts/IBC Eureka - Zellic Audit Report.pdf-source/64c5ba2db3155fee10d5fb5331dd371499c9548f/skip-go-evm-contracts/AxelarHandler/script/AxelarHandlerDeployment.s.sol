// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Environment} from "test/Environment.sol";

import {AxelarHandler} from "src/AxelarHandler.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AxelarHandlerDeploymentScript is Script {
    Environment public env;
    AxelarHandler public handler;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        env = new Environment();
        env.setEnv(block.chainid);
    }

    function run() public {
        address gateway = env.gateway();
        address gasService = env.gasService();
        string memory wethSymbol = env.wethSymbol();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        AxelarHandler handlerImpl = new AxelarHandler();
        ERC1967Proxy handlerProxy = new ERC1967Proxy(
            address(handlerImpl),
            abi.encodeWithSignature(
                "initialize(address,address,string)",
                gateway,
                gasService,
                wethSymbol
            )
        );
        handler = AxelarHandler(payable(address(handlerProxy)));
        vm.stopBroadcast();

        console2.log("Axelar Handler Address: ", address(handler));
    }
}
