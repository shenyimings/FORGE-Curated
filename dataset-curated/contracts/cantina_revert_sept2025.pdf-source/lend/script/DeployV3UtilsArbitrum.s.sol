// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployV3UtilsArbitrum is Script {
    function run() external {
        // Hardcoded Arbitrum mainnet addresses
        address nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // Same on all EVM chains
        address universalRouter = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223; // Arbitrum Universal Router 
        address zeroxAllowanceHolder = 0x0000000000001fF3684f28c67538d4D072C22734; // 0x AllowanceTarget Arbitrum 
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Same on all EVM chains


        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy V3Utils
        V3Utils v3Utils = new V3Utils(
            INonfungiblePositionManager(nonfungiblePositionManager),
            universalRouter,
            zeroxAllowanceHolder,
            permit2
        );

        // Log deployment information
        console.log("V3Utils deployed to:", address(v3Utils));
        console.log("Owner:", v3Utils.owner());

        vm.stopBroadcast();
    }
}