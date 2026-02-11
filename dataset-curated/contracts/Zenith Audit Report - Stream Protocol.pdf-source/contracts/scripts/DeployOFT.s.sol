// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MyOFT} from "../src/OFT.sol";
import {console2} from "forge-std/console2.sol";

contract DeployOFTScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy OFT for wrapped tokens (StableWrapper)
        address lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f; // Base Sepolia LZ Endpoint
        MyOFT wrappedOFT = new MyOFT(
            "Wrapped Test USD", 
            "wTESTUSD",
            lzEndpoint,
            deployer,  // delegate
            6  // decimals
        );
        console2.log("Wrapped OFT deployed to:", address(wrappedOFT));

        // Deploy OFT for staked tokens (StreamVault)
        MyOFT stakedOFT = new MyOFT(
            "Stream Vault Token",
            "svToken",
            lzEndpoint,
            deployer,  // delegate
            6  // decimals
        );
        console2.log("Staked OFT deployed to:", address(stakedOFT));

        vm.stopBroadcast();

        console2.log("\nDeployment Summary:");
        console2.log("-------------------");
        console2.log("Wrapped OFT:", address(wrappedOFT));
        console2.log("Staked OFT:", address(stakedOFT));
    }
}