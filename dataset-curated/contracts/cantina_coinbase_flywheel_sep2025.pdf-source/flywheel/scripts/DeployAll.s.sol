// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployFlywheel} from "./DeployFlywheel.s.sol";
import {DeployBuilderCodes} from "./DeployBuilderCodes.s.sol";
import {DeployAdConversion} from "./DeployAdConversion.s.sol";
import {DeploySimpleRewards} from "./DeploySimpleRewards.s.sol";
import {DeployCashbackRewards} from "./DeployCashbackRewards.s.sol";

/// @notice Script for deploying all Flywheel protocol contracts in the correct order
contract DeployAll is Script {
    /// @notice Deployment information structure
    struct DeploymentInfo {
        address flywheel;
        address referralCodes;
        address adConversion;
        address cashbackRewards;
        address simpleRewards;
    }

    function run() external {
        address owner = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;
        address signerAddress = 0x0000000000000000000000000000000000000000;
        string memory uriPrefix = "https://flywheel.com/";
        run(owner, signerAddress, uriPrefix);
    }

    /// @notice Deploys all contracts in the correct order
    /// @param owner Address that will own the contracts
    /// @param signerAddress Address authorized to call registerPublisherCustom (can be zero address)
    function run(address owner, address signerAddress, string memory uriPrefix)
        public
        returns (DeploymentInfo memory info)
    {
        address escrow = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;
        require(owner != address(0), "Owner cannot be zero address");

        console.log("Starting deployment of Flywheel protocol contracts...");
        console.log("Owner address:", owner);
        console.log("Signer address:", signerAddress);
        console.log("URI Prefix:", uriPrefix);
        console.log("AuthCaptureEscrow:", escrow);
        console.log("==========================================");

        // Deploy Flywheel first (independent contract)
        console.log("1. Deploying Flywheel...");
        DeployFlywheel flywheelDeployer = new DeployFlywheel();
        info.flywheel = flywheelDeployer.run();

        // Deploy BuilderCodes (independent contract)
        console.log("2. Deploying BuilderCodes...");
        DeployBuilderCodes registryDeployer = new DeployBuilderCodes();
        info.referralCodes = registryDeployer.run(owner, signerAddress, uriPrefix);

        // Deploy AdConversion hook (depends on both Flywheel and BuilderCodes)
        console.log("3. Deploying AdConversion hook...");
        DeployAdConversion adConversionDeployer = new DeployAdConversion();
        info.adConversion = adConversionDeployer.run(info.flywheel, owner, info.referralCodes);

        // Deploy CashbackRewards hook (depends on Flywheel and AuthCaptureEscrow)
        console.log("4. Deploying CashbackRewards hook...");
        DeployCashbackRewards cashbackRewardsDeployer = new DeployCashbackRewards();
        info.cashbackRewards = cashbackRewardsDeployer.run(info.flywheel, escrow);

        // Deploy SimpleRewards hook (depends on Flywheel)
        console.log("5. Deploying SimpleRewards hook...");
        DeploySimpleRewards simpleRewardsDeployer = new DeploySimpleRewards();
        info.simpleRewards = simpleRewardsDeployer.run(info.flywheel);

        console.log("==========================================");
        console.log("Deployment complete!");
        console.log("Flywheel:", info.flywheel);
        console.log("BuilderCodes:", info.referralCodes);
        console.log("AdConversion:", info.adConversion);
        console.log("CashbackRewards:", info.cashbackRewards);
        console.log("SimpleRewards:", info.simpleRewards);

        return info;
    }
}
