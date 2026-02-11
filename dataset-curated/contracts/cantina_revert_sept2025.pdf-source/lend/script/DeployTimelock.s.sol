// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployTimelock is Script {
    function run() external {
        vm.startBroadcast();

        // Multisig that will control the timelock
        address multisig = 0x3e456ED2793988dc08f1482371b50bA2bC518175;
        
        // Setup arrays for proposers and executors
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        TimelockController timelock = new TimelockController(
            48 hours,    // minDelay (172800 seconds)
            proposers,   // proposers array [multisig]
            executors,   // executors array [multisig]
            multisig     // admin
        );

        console.log("Timelock deployed at:", address(timelock));
        console.log("Configured for multisig:", multisig);
        console.log("Delay:", 48, "hours");

        vm.stopBroadcast();
    }
} 