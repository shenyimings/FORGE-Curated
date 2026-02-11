// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployV3UtilsMainnet is Script {
    function run() external {
        // Hardcoded Ethereum mainnet addresses
        address nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // Mainnet NPM
        address universalRouter = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af; // Mainnet Universal Router
        address zeroxAllowanceHolder = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // Mainnet 0x Proxy
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Same Permit2 address across chains

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