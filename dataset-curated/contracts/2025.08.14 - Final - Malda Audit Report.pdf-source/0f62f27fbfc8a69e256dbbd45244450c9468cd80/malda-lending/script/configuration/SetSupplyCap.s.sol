// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Operator} from "src/Operator/Operator.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetSupplyCap is Script {
    function run(address operator, address market, uint256 cap) public {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        address[] memory mTokens = new address[](1);
        uint256[] memory caps = new uint256[](1);
        mTokens[0] = market;
        caps[0] = cap;

        console.log("Setting supply cap for market", market);

        if (Operator(operator).supplyCaps(market) == cap) {
            console.log("Supply cap already set");
            return;
        }

        vm.startBroadcast(key);
        Operator(operator).setMarketSupplyCaps(mTokens, caps);
        vm.stopBroadcast();

        console.log(" Supply cap set for market %s", market);

    }
}
