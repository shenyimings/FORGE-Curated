// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployV3UtilsBNB is Script {
    function run() external {
        // Hardcoded BNB Chain mainnet addresses
        address nonfungiblePositionManager = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613; // BNB NPM
        address universalRouter = 0x1906c1d672b88cD1B9aC7593301cA990F94Eae07; // BNB Universal Router
        address zeroxAllowanceHolder = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // BNB 0x Proxy
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Same Permit2 address across chains


        address wbnb = INonfungiblePositionManager(nonfungiblePositionManager).WETH9();
        console.log("WBNB address from NPM:", wbnb);

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
        console.log("WBNB address from V3Utils:", address(v3Utils.weth()));

        vm.stopBroadcast();
    }
} 