// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Flywheel} from "../src/Flywheel.sol";

/// @notice Script for deploying the Flywheel contract
contract DeployFlywheel is Script {
    /// @notice Deploys the Flywheel contract
    function run() external returns (address) {
        vm.startBroadcast();

        // Deploy Flywheel contract (constructor automatically deploys TokenStore implementation)
        Flywheel flywheel = new Flywheel();

        console.log("Flywheel deployed at:", address(flywheel));
        console.log("Campaign implementation at:", flywheel.campaignImplementation());

        vm.stopBroadcast();

        return (address(flywheel));
    }
}
