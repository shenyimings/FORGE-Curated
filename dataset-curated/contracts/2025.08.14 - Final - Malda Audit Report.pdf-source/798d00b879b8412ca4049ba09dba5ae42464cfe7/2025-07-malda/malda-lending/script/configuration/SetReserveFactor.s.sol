// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {mTokenConfiguration} from "src/mToken/mTokenConfiguration.sol";
import "forge-std/Script.sol";

contract SetReserveFactor is Script {
    function run(address market, uint256 factor) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        console.log("Setting reserve factor for market", market);

        vm.startBroadcast(key);
        mTokenConfiguration(market).setReserveFactor(factor);
        vm.stopBroadcast();

        console.log("Set reserve factor for market", market);
    }
}
