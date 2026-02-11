// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { CompoundLens } from "../../../src/contracts/Lens/CompoundLens.sol";

/**
 * @title DeployCompoundLens
 * @notice Script to deploy the CompoundLens contract for querying protocol state
 * @dev The CompoundLens is a utility contract that provides view functions to query protocol state
 */
contract DeployCompoundLens is Script {
    function run(address account) external returns (address) {
        console.log("Deploying CompoundLens with account:", account);
        
        vm.startBroadcast(account);
        
        // Deploy CompoundLens
        CompoundLens lens = new CompoundLens();
        
        vm.stopBroadcast();
        
        console.log("CompoundLens deployed at:", address(lens));
        
        return address(lens);
    }
} 