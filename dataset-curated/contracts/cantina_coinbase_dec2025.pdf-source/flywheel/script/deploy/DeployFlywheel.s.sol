// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Flywheel} from "../../src/Flywheel.sol";

/// @notice Script for deploying the Flywheel contract
contract DeployFlywheel is Script {
    /// @notice Deploys the Flywheel contract
    function run() external returns (address) {
        vm.startBroadcast();

        address expectedAddress = 0x00000F14AD09382841DB481403D1775ADeE1179F;

        // Deploy Flywheel contract (constructor automatically deploys TokenStore implementation)
        Flywheel flywheel = new Flywheel{salt: 0x50d3d32f74850fcf5d18f0c292f32aab8f8cb20e4fabd3a9c1b11e4aaf7fa680}();

        console.log("Flywheel deployed at:", address(flywheel));
        console.log("Campaign implementation deployed at:", flywheel.CAMPAIGN_IMPLEMENTATION());

        assert(address(flywheel) == expectedAddress);

        vm.stopBroadcast();

        return (address(flywheel));
    }
}
