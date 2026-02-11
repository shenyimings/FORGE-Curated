// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { Comptroller } from "../../../src/contracts/Comptroller.sol";
import { CToken } from "../../../src/contracts/CToken.sol";
import { CErc20 } from "../../../src/contracts/CErc20.sol";
import { CEther } from "../../../src/contracts/CEther.sol";
import { ChainlinkPriceOracle } from "../../../src/contracts/PriceOracle/ChainlinkPriceOracle.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../../HelperConfig.s.sol";
import { Config } from "../config/Config.sol";
import { ProdConfig } from "../config/ProdConfig.sol";
import { CustomConfig } from "../config/CustomConfig.sol";


/**
 * @title AddChainlinkPriceOracle
 * @notice Adds Chainlink price feeds for a cToken in the price oracle
 * @dev To be used for adding price oracle configs for cTokens
 */
contract AddChainlinkPriceOracle is Script {
    error TokenNotFound(string tokenSymbol);
    
    function run(address account, string memory tokenSymbol) external {
        console.log("Adding Chainlink price oracle config for token: %s", tokenSymbol);
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
        
        // Get the oracle address
        address oracleAddress = networkConfig.oracle;
        console.log("Oracle address: %s", oracleAddress);
        require(oracleAddress != address(0), "Oracle address not set in config");
        
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
            console.log("Cannot add price oracle config without configuration");
            return;
        }

        Config.chainlinkOracleConfig memory oracleConfig = cTokenInfo.config.chainlinkOracleConfig;
        
        console.log("Found Chainlink config for %s:", tokenSymbol);
        console.log("  Underlying asset decimals: %s", oracleConfig.underlyingAssetDecimals);
        console.log("  Price feed: %s", oracleConfig.priceFeed);
        console.log("  Fixed price: %s", oracleConfig.fixedPrice);
        

        ChainlinkPriceOracle.LoadConfig memory loadConfig = ChainlinkPriceOracle.LoadConfig({
            cToken: cTokenAddress,
            underlyingAssetDecimals: oracleConfig.underlyingAssetDecimals,
            priceFeed: oracleConfig.priceFeed,
            fixedPrice: oracleConfig.fixedPrice
        });

        vm.startBroadcast(account);

        try ChainlinkPriceOracle(oracleAddress).addConfig(loadConfig) {
            console.log("Config added to oracle");
        } catch (bytes memory reason) {
            console.logBytes(reason);
        }

        vm.stopBroadcast();
        console.log("Chainlink oracle configuration successfully set for %s!", tokenSymbol);
    }
} 