// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CapyfiAggregatorV3 } from "../../src/contracts/PriceOracle/CapyfiAggregatorV3.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../HelperConfig.s.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { Config } from "./config/Config.sol";

/**
 * @title DeployCapyfiAggregatorV3
 * @notice Deploys CapyfiAggregatorV3 price oracles for UXD and LAC tokens
 * 
 * @dev Usage Examples:
 * 
 * Deploy both UXD and LAC aggregators:
 * forge script script/capyfi/DeployCapyfiAggregatorV3.s.sol:DeployCapyfiAggregatorV3 --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY
 */
contract DeployCapyfiAggregatorV3 is Script {

    struct DeployedAggregators {
        address uxdAggregator;
        address lacAggregator;
    }

    DeployedAggregators public deployedAggregators;

    function run(address account) external returns (DeployedAggregators memory) {
        console.log("Deploying CapyfiAggregatorV3 oracles with account:", account);
        
        // Get configuration based on chain ID
        HelperConfig helperConfig = new HelperConfig();
        Config config = helperConfig.getConfigBasedOnNetwork();
     
        Config.CapyfiAggregatorConfig[] memory aggregatorConfigs = config.getCapyfiAggregators();
        
        vm.startBroadcast(account);
        
        // Deploy UXD Aggregator
        Config.CapyfiAggregatorConfig memory uxdConfig = aggregatorConfigs[0];
        CapyfiAggregatorV3 uxdAggregator = new CapyfiAggregatorV3(
            uxdConfig.decimals,
            uxdConfig.description,
            uxdConfig.version,
            uxdConfig.initialPrice
        );
        deployedAggregators.uxdAggregator = address(uxdAggregator);
        
        console.log("UXD CapyfiAggregatorV3 deployed at:", deployedAggregators.uxdAggregator);
        console.log("- Description:", uxdConfig.description);
        console.log("- Decimals:", uxdConfig.decimals);
        console.log("- Initial Price:", uint256(uxdConfig.initialPrice));
        
        // Deploy LAC Aggregator
        Config.CapyfiAggregatorConfig memory lacConfig = aggregatorConfigs[1];
        CapyfiAggregatorV3 lacAggregator = new CapyfiAggregatorV3(
            lacConfig.decimals,
            lacConfig.description,
            lacConfig.version,
            lacConfig.initialPrice
        );
        deployedAggregators.lacAggregator = address(lacAggregator);
        
        console.log("LAC CapyfiAggregatorV3 deployed at:", deployedAggregators.lacAggregator);
        console.log("- Description:", lacConfig.description);
        console.log("- Decimals:", lacConfig.decimals);
        console.log("- Initial Price:", uint256(lacConfig.initialPrice));
        
        vm.stopBroadcast();
        
        return deployedAggregators;
    }
} 