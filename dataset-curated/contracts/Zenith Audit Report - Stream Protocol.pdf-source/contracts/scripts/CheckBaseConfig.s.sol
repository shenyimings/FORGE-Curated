// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IMessageLibManager} from "lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";

contract CheckBaseConfigScript is Script {
    function run() public view {
        // Base Sepolia LayerZero Endpoint
        IMessageLibManager endpoint = IMessageLibManager(0x6EDCE65403992e310A62460808c4b910D972f10f);

        // StreamVault on Base
        address baseVault = 0x2B890881268172d1697eB7bc9744F8424E5A3f5a;

        // Get receive library for receiving from Arbitrum
        (address receiveLib, bool isDefault) = endpoint.getReceiveLibrary(baseVault, 40231);
        console2.log("Base Receive Library:", receiveLib);
        console2.log("Is Default:", isDefault);

        // Get config
        bytes memory receiveConfig = endpoint.getConfig(baseVault, receiveLib, 40231, 2);
        console2.log("Base Receive Config:", vm.toString(receiveConfig));
    }
} 