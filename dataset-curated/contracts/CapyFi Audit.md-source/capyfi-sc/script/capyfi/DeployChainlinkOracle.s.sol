// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { ChainlinkPriceOracle } from "../../src/contracts/PriceOracle/ChainlinkPriceOracle.sol";
import { PriceOracle } from "../../src/contracts/PriceOracle.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../HelperConfig.s.sol";

/**
 * @title DeployChainlinkOracle
 * @notice Deploys ChainlinkPriceOracle with configurable price feeds
 */
contract DeployChainlinkOracle is Script {
    address public oracleAddress;

    function run(address account) external returns (address) {
        console.log("Deploying ChainlinkPriceOracle with account:", account);
        
        // Get network configuration
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        
        vm.startBroadcast(account);
        
        // Deploy oracle with price feeds
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle(new ChainlinkPriceOracle.LoadConfig[](0));
        oracleAddress = address(priceOracle);
        
        console.log("ChainlinkPriceOracle deployed at:", oracleAddress);
        
        // If unitroller is set, update it to use the new oracle
        if (networkConfig.unitroller != address(0)) {
            console.log("Setting price oracle in comptroller at:", networkConfig.unitroller);
            Comptroller comptroller = Comptroller(networkConfig.unitroller);
            comptroller._setPriceOracle(PriceOracle(oracleAddress));
            console.log("Price oracle updated in comptroller");
        }
        
        vm.stopBroadcast();
        
        return oracleAddress;
    }
}
