// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DefaultGasHelper} from "src/oracles/gas/DefaultGasHelper.sol";

contract SetGasFees is Script {
    function run() public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        address gasHelper = address(0); // update when deployed

        uint32[] memory routes = new uint32[](3);
        routes[0] = 8453;
        routes[1] = 59144;
        routes[2] = 1;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 83338358600000;
        amounts[1] = 108904397956204;
        amounts[2] = 3497531544510113;

        console.log("Set gas destination fees");
        vm.startBroadcast(key);
        for (uint256 j; j < routes.length; j++) {
            DefaultGasHelper(gasHelper).setGasFee(routes[j], amounts[j]);
        }
        vm.stopBroadcast();
        console.log("Gas fees set");
    }
}
