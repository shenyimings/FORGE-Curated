// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {IMessageLibManager} from "lib/layerzero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";

contract SetLibraryScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Arbitrum Sepolia LayerZero Endpoint
        IMessageLibManager endpoint = IMessageLibManager(0x6EDCE65403992e310A62460808c4b910D972f10f);

        vm.startBroadcast(deployerPrivateKey);

        // Set send library on the endpoint
        endpoint.setSendLibrary(
            0x58107a168E54802A7D35ebDBE6e9f82447d5Fb8d,  // StreamVault address
            40245,                                        // destination EID
            0x4f7cd4DA19ABB31b0eC98b9066B9e857B1bf9C0E   // send library
        );

        vm.stopBroadcast();
    }
}
