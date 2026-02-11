// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IMessageLibManager} from "lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";

contract CheckArbConfigScript is Script {
    function run() public view {
        // Arbitrum Sepolia LayerZero Endpoint
        IMessageLibManager endpoint = IMessageLibManager(0x6EDCE65403992e310A62460808c4b910D972f10f);

        // StreamVault on Arbitrum
        address arbVault = 0x58107a168E54802A7D35ebDBE6e9f82447d5Fb8d;

        // Get send library for sending to Base
        address sendLib = endpoint.getSendLibrary(arbVault, 40245);
        console2.log("Arb Send Library:", sendLib);

        // Get config
        bytes memory sendConfig = endpoint.getConfig(arbVault, sendLib, 40245, 2);
        console2.log("Arb Send Config:", vm.toString(sendConfig));

        // Also check if the library is registered
        bool isRegistered = endpoint.isRegisteredLibrary(sendLib);
        console2.log("Is Send Library Registered:", isRegistered);
    }
}