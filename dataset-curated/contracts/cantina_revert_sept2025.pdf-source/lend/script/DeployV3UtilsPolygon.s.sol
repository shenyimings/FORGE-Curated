// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployV3UtilsPolygon is Script {
    function run() external {
        // Hardcoded Polygon mainnet addresses
        address nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
        address universalRouter = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
        address zeroxAllowanceHolder = 0x0000000000001fF3684f28c67538d4D072C22734;
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;


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