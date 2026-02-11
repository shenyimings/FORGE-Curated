// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployAdConversion} from "./DeployAdConversion.s.sol";
import {DeployBridgeReferralFees} from "./DeployBridgeReferralFees.s.sol";
import {DeployCashbackRewards} from "./DeployCashbackRewards.s.sol";
import {DeployFlywheel} from "./DeployFlywheel.s.sol";
import {DeploySimpleRewards} from "./DeploySimpleRewards.s.sol";

/// @notice Script for deploying all Flywheel protocol contracts in the correct order
contract DeployAll is Script {
    /// @notice Deployment information structure
    struct Deployments {
        address flywheel;
        address adConversion;
        address cashbackRewards;
        address bridgeReferralFees;
        address simpleRewards;
    }

    // forge script DeployAll --sig "run(address)" builderCodes
    function run(address builderCodes) public returns (Deployments memory deployments) {
        require(builderCodes != address(0), "BuilderCodes cannot be zero address");

        console.log("Starting deployment of Flywheel protocol contracts...");
        console.log("Builder Codes:", builderCodes);
        console.log("==========================================");

        // Deploy Flywheel first (no dependencies)
        console.log("1. Deploying Flywheel...");
        DeployFlywheel flywheelDeployer = new DeployFlywheel();
        deployments.flywheel = flywheelDeployer.run();

        // Deploy AdConversion (depends on Flywheel, BuilderCodes)
        console.log("2. Deploying AdConversion...");
        DeployAdConversion adConversionDeployer = new DeployAdConversion();
        deployments.adConversion = adConversionDeployer.run(deployments.flywheel, builderCodes);

        // Deploy CashbackRewards (depends on Flywheel)
        console.log("3. Deploying CashbackRewards...");
        DeployCashbackRewards cashbackRewardsDeployer = new DeployCashbackRewards();
        deployments.cashbackRewards = cashbackRewardsDeployer.run(deployments.flywheel);

        // Deploy SimpleRewards (depends on Flywheel)
        console.log("4. Deploying SimpleRewards...");
        DeploySimpleRewards simpleRewardsDeployer = new DeploySimpleRewards();
        deployments.simpleRewards = simpleRewardsDeployer.run(deployments.flywheel);

        // Deploy BridgeReferralFees (depends on Flywheel, BuilderCodes)
        console.log("5. Deploying BridgeReferralFees...");
        DeployBridgeReferralFees bridgeReferralFeesDeployer = new DeployBridgeReferralFees();
        deployments.bridgeReferralFees = bridgeReferralFeesDeployer.run(deployments.flywheel, builderCodes);

        console.log("==========================================");
        console.log("Deployment complete!");
        console.log("Flywheel:", deployments.flywheel);
        console.log("AdConversion:", deployments.adConversion);
        console.log("CashbackRewards:", deployments.cashbackRewards);
        console.log("SimpleRewards:", deployments.simpleRewards);
        console.log("BridgeReferralFees:", deployments.bridgeReferralFees);

        return deployments;
    }
}
