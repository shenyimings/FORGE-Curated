// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";

import {VeloraAdapter} from "src/periphery/VeloraAdapter.sol";
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {DeployConstants} from "./DeployConstants.sol";

contract PeripheryDeploy is Script {
    function run() public {
        address deployerAddress = msg.sender;

        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);
        console.log("DeployerAddress: ", deployerAddress);

        console.log("Deploying...");

        vm.startBroadcast();

        VeloraAdapter veloraAdapter = new VeloraAdapter(DeployConstants.AUGUSTUS_REGISTRY);
        console.log("VeloraAdapter deployed at: ", address(veloraAdapter));

        LeverageRouter leverageRouter =
            new LeverageRouter(ILeverageManager(DeployConstants.LEVERAGE_MANAGER), IMorpho(DeployConstants.MORPHO));
        console.log("LeverageRouter deployed at: ", address(leverageRouter));

        vm.stopBroadcast();
    }
}
