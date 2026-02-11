pragma solidity 0.8.15;

import {Script} from "forge-std/Script.sol";

contract ScriptUtils is Script {
    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }
}
