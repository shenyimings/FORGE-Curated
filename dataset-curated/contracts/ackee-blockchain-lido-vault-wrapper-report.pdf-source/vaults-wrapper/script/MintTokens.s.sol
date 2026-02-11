// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockERC20} from "../test/mocks/MockERC20.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract MintTokensScript is Script {
    function run() external {
        address tokenAddress = 0x262e2b50219620226C5fB5956432A88fffd94Ba7;
        address distributorAddress = 0x10e38eE9dd4C549b61400Fc19347D00eD3edAfC4;
        uint256 amount = 9999999999;
        uint256 privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        console.log("=== Token Minting Script ===");
        console.log("Token Address:", tokenAddress);
        console.log("Distributor Address:", distributorAddress);
        console.log("Amount:", amount);
        console.log("Private Key:", privateKey);
        console.log("");

        vm.startBroadcast(privateKey);

        MockERC20 token = MockERC20(tokenAddress);

        console.log("Minting tokens...");
        token.mint(distributorAddress, amount);

        uint256 balance = token.balanceOf(distributorAddress);
        console.log("New balance of distributor:", balance);

        vm.stopBroadcast();

        console.log("Minting completed successfully!");
    }
}
