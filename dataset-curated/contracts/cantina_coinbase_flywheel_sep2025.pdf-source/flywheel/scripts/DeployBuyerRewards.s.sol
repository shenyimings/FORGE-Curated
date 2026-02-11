// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CashbackRewards} from "../src/hooks/CashbackRewards.sol";

/// @notice Script for deploying the CashbackRewards hook contract
contract DeployCashbackRewards is Script {
    /// @notice Deploys the CashbackRewards hook
    /// @param flywheel Address of the deployed Flywheel contract
    function run(address flywheel, address escrow) external returns (address) {
        require(flywheel != address(0), "Flywheel cannot be zero address");

        vm.startBroadcast();

        // Deploy CashbackRewards hook
        CashbackRewards hook = new CashbackRewards(flywheel, escrow);
        console.log("CashbackRewards hook deployed at:", address(hook));

        vm.stopBroadcast();

        return address(hook);
    }
}
