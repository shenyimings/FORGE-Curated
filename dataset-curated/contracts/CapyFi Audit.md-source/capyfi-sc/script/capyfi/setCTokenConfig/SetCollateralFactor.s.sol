// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { Comptroller } from "../../../src/contracts/Comptroller.sol";
import { CToken } from "../../../src/contracts/CToken.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../../HelperConfig.s.sol";
import { Config } from "../config/Config.sol";
import { ProdConfig } from "../config/ProdConfig.sol";
import { CustomConfig } from "../config/CustomConfig.sol";

/**
 * @title SetCollateralFactor
 * @notice Sets the collateral factor for a cToken in the Comptroller
 * @dev To be used for configuring collateral factor of a cToken
 */
contract SetCollateralFactor is Script {
    error TokenNotFound(string tokenSymbol);
    
    function run(address account, string memory tokenSymbol) external {
        console.log("Setting collateral factor for token: %s", tokenSymbol);
        console.log("Using account: %s", account);

        // Setup configurations
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        
        // Get the cToken address based on the token symbol using HelperConfig's function
        address cTokenAddress = helperConfig.getCTokenAddressBySymbol(networkConfig, tokenSymbol);
        if (cTokenAddress == address(0)) {
            revert TokenNotFound(tokenSymbol);
        }
        console.log("Found cToken address: %s", cTokenAddress);
        
        // Get the unitroller/comptroller address
        address unitrollerAddress = networkConfig.unitroller;
        console.log("Unitroller address: %s", unitrollerAddress);
        require(unitrollerAddress != address(0), "Unitroller address not set in config");
        
        // Select appropriate config based on network
        Config config;
        config = helperConfig.getConfigBasedOnNetwork();


        // Find token config based on cToken symbol
        Config.CTokenInfo memory cTokenInfo;
        bool foundConfig = false;
        string memory cTokenSymbol = string(abi.encodePacked("ca", tokenSymbol));

        Config.CTokenInfo[] memory allTokens = config.getCTokens();
        for (uint i = 0; i < allTokens.length; i++) {
            if (keccak256(abi.encodePacked(allTokens[i].args.symbol)) == keccak256(abi.encodePacked(cTokenSymbol))) {
                cTokenInfo = allTokens[i];
                foundConfig = true;
                break;
            }
        }

        if (!foundConfig) {
            console.log("Warning: No configuration found for token:", cTokenSymbol);
            console.log("Cannot set collateral factor without configuration");
            return;
        }

        console.log("Found collateral factor for %s: %s", tokenSymbol, cTokenInfo.config.collateralFactor);
        
        vm.startBroadcast(account);

        // Set collateral factor in Comptroller
        Comptroller comptroller = Comptroller(unitrollerAddress);
        comptroller._setCollateralFactor(CToken(cTokenAddress), cTokenInfo.config.collateralFactor);
        
        vm.stopBroadcast();
        console.log("Collateral factor successfully set for %s to %s!", tokenSymbol, cTokenInfo.config.collateralFactor);
    }
} 