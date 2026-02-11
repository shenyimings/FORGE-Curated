// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/InterestRateModel.sol";

contract DeployInterestRateModelUpdate is Script {
    uint256 constant Q64 = 2 ** 64;

    function run() external {
        vm.startBroadcast();

        InterestRateModel model = new InterestRateModel(
            0,                      // base rate (0%)
            Q64 * 13 / 100,        // multiplier (13%)
            Q64 * 300 / 100,       // jump multiplier (300%)
            Q64 * 90 / 100         // kink (90%)
        );

        console.log("InterestRateModel deployed at:", address(model));

        vm.stopBroadcast();
    }
} 