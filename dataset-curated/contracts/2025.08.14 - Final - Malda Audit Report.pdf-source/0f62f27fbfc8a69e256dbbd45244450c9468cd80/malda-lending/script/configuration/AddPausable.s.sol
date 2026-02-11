// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Pauser} from "src/pauser/Pauser.sol";
import {IPauser} from "src/interfaces/IPauser.sol";
import {Script, console} from "forge-std/Script.sol";

contract AddPausable is Script {
    function run(address ctr, address market, bool extension) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        Pauser pauser = Pauser(ctr);
        vm.startBroadcast(key);
        pauser.addPausableMarket(market, extension ? IPauser.PausableType.Extension : IPauser.PausableType.Host);
        vm.stopBroadcast();

        console.log(" Added pausable market %s", market);
    }
}
