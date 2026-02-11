// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {PricingAdapter} from "src/periphery/PricingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {DeployConstants} from "./DeployConstants.sol";

contract DeployPricingAdapter is Script {
    function run() public {
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast();

        address deployerAddress = msg.sender;
        console.log("DeployerAddress: ", deployerAddress);

        PricingAdapter pricingAdapter = new PricingAdapter(ILeverageManager(DeployConstants.LEVERAGE_MANAGER));
        console.log("PricingAdapter deployed at: ", address(pricingAdapter));

        vm.stopBroadcast();
    }
}
