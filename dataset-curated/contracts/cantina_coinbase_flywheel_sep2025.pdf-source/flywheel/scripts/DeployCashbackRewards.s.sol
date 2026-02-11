// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CashbackRewards} from "../src/hooks/CashbackRewards.sol";

/// @notice Script for deploying the CashbackRewards hook contract
contract DeployCashbackRewards is Script {
    // function run(address flywheel, address escrow) external returns (address) {
    function run() external returns (address) {
        // require(flywheel != address(0), "Flywheel cannot be zero address");
        address flywheel = 0xB04d55fCc15569B23B8B8C05068C7dAb2B9028D8;
        address escrow = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;

        vm.startBroadcast();

        // Deploy CashbackRewards hook
        CashbackRewards hook = new CashbackRewards(flywheel, escrow);
        console.log("CashbackRewards hook deployed at:", address(hook));

        vm.stopBroadcast();

        return address(hook);
    }
}
