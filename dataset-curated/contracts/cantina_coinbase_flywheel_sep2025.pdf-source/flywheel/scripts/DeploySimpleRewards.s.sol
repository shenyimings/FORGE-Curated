// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {SimpleRewards} from "../src/hooks/SimpleRewards.sol";

/// @notice Script for deploying the SimpleRewards hook contract
contract DeploySimpleRewards is Script {
    /// @notice Deploys the SimpleRewards hook
    /// @param flywheel Address of the deployed Flywheel contract
    function run(address flywheel) external returns (address) {
        require(flywheel != address(0), "Flywheel cannot be zero address");

        vm.startBroadcast();

        // Deploy SimpleRewards hook
        SimpleRewards hook = new SimpleRewards(flywheel);
        console.log("SimpleRewards hook deployed at:", address(hook));

        vm.stopBroadcast();

        return address(hook);
    }
}
