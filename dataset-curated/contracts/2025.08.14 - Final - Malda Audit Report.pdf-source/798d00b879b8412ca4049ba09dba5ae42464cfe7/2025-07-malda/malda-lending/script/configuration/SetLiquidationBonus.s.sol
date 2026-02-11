// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Operator} from "src/Operator/Operator.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetLiquidationBonus is Script {
    function run(address operator, address market, uint256 factor) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        console.log("Setting liquidation incentives for market", market);

        vm.startBroadcast(key);
        Operator(operator).setLiquidationIncentive(market, factor);
        vm.stopBroadcast();

        console.log("Set liquidation incentives for market", market);
    }
}
