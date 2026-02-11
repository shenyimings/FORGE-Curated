// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Operator} from "src/Operator/Operator.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetCollateralFactor is Script {
    function run(address operator, address market, uint256 factor) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        console.log("Setting collateral factor for market", market);

        (, uint256 currentFactor,) = Operator(operator).markets(market);

        if (currentFactor == factor) {
            console.log("Collateral factor already set");
            return;
        }

        vm.startBroadcast(key);
        Operator(operator).setCollateralFactor(market, factor);
        vm.stopBroadcast();

        console.log("Set collateral factor for market", market);
    }
}
