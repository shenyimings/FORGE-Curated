// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CashbackRewards} from "../../src/hooks/CashbackRewards.sol";

/// @notice Script for deploying the CashbackRewards hook contract
contract DeployCashbackRewards is Script {
    function run(address flywheel) external returns (address) {
        require(flywheel != address(0), "Flywheel cannot be zero address");

        address escrow = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;
        console.log("AuthCaptureEscrow:", escrow);

        vm.startBroadcast();

        // Deploy CashbackRewards hook
        CashbackRewards hook = new CashbackRewards{salt: 0}(flywheel, escrow);
        console.log("CashbackRewards deployed at:", address(hook));

        vm.stopBroadcast();

        return address(hook);
    }
}
