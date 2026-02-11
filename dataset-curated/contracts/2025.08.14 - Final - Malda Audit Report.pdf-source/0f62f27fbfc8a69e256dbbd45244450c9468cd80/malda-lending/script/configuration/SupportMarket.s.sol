// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Operator} from "src/Operator/Operator.sol";
import {Script, console} from "forge-std/Script.sol";

contract SupportMarket is Script {
    function run(address operator, address market) public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        console.log("Supporting market", market);

        (bool isListed,,) = Operator(operator).markets(market);

        if (isListed) {
            console.log("Market already supported");
            return;
        }

        vm.startBroadcast(key);
        Operator(operator).supportMarket(market);
        vm.stopBroadcast();

        console.log("Supported market:", market);
    }
}
