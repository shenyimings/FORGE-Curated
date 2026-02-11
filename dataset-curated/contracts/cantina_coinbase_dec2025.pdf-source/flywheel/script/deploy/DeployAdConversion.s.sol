// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {AdConversion} from "../../src/hooks/AdConversion.sol";

/// @notice Script for deploying the AdConversion hook contract
contract DeployAdConversion is Script {
    /// @notice Deploys the AdConversion hook
    /// @param flywheel Address of the deployed Flywheel contract
    /// @param builderCodes Address of the deployed BuilderCodes contract
    function run(address flywheel, address builderCodes) external returns (address) {
        require(flywheel != address(0), "Flywheel cannot be zero address");
        require(builderCodes != address(0), "BuilderCodes cannot be zero address");

        vm.startBroadcast();

        // Deploy AdConversion hook
        AdConversion hook = new AdConversion{salt: 0}(flywheel, builderCodes);
        console.log("AdConversion deployed at:", address(hook));

        vm.stopBroadcast();

        return address(hook);
    }
}
