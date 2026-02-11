// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CErc20Delegator } from "../../src/contracts/CErc20Delegator.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { SimplePriceOracle } from "../../src/contracts/SimplePriceOracle.sol";
import { ChainlinkPriceOracle } from "../../src/contracts/PriceOracle/ChainlinkPriceOracle.sol";
import { CToken } from "../../src/contracts/CToken.sol";
import { Config } from "./config/Config.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../HelperConfig.s.sol";

/**
 * @title ConfigureCToken
 * @notice Configures a cToken including market support, price feed, collateral factor, and reserve factor
 * @dev Supports both SimplePriceOracle and ChainlinkPriceOracle
 */
contract ConfigureCToken is Script {
    error TokenNotFound(string tokenSymbol);


    function run(address account, string memory tokenSymbol) external {
        console.log("Configuring cToken %s with account: %s", tokenSymbol, account);

        // Setup configurations
        Config config;
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        address cTokenAddress = helperConfig.getCTokenAddressBySymbol(networkConfig, tokenSymbol);
        if (cTokenAddress == address(0)) {
            revert TokenNotFound(tokenSymbol);
        }
        console.log("Found cToken address: %s", cTokenAddress);

        config = helperConfig.getConfigBasedOnNetwork();

        // Find token config based on cToken address
        Config.CTokenInfo memory cTokenInfo;
        bool foundConfig = false;

        // Get the cToken symbol for better identification
        string memory cTokenSymbol = string(abi.encodePacked("c", tokenSymbol));
        console.log("Configuring token with symbol: %s", cTokenSymbol);

        Config.CTokenInfo[] memory allTokens = config.getCTokens();
        for (uint i = 0; i < allTokens.length; i++) {
            if (keccak256(abi.encodePacked(allTokens[i].args.symbol)) == keccak256(abi.encodePacked(cTokenSymbol))) {
                cTokenInfo = allTokens[i];
                foundConfig = true;
                break;
            }
        }

        require(foundConfig, "No configuration found for this cToken");

        vm.startBroadcast(account);

        console.log("Found configuration for token:", cTokenSymbol);
        
        // Get the unitroller from config or from token
        address unitrollerAddress = networkConfig.unitroller;
     
        // 1. Support market in Comptroller
        Comptroller comptroller = Comptroller(unitrollerAddress);
        comptroller._supportMarket(CToken(cTokenAddress));
        console.log("Market supported in Comptroller");
    
        // 2. Set collateral factor if applicable
        if (cTokenInfo.config.collateralFactor > 0) {
            comptroller._setCollateralFactor(CToken(cTokenAddress), cTokenInfo.config.collateralFactor);
            console.log("Collateral factor set: %s", cTokenInfo.config.collateralFactor);
        } else {
            console.log("Skipping collateral factor (set to 0)");
        }

        // 3. addConfig() in oracle chaininkpriceOracle
        ChainlinkPriceOracle oracle = ChainlinkPriceOracle(networkConfig.oracle);

        ChainlinkPriceOracle.LoadConfig memory loadConfig = ChainlinkPriceOracle.LoadConfig({
            cToken: cTokenAddress,
            underlyingAssetDecimals: cTokenInfo.config.chainlinkOracleConfig.underlyingAssetDecimals,
            priceFeed: cTokenInfo.config.chainlinkOracleConfig.priceFeed,
            fixedPrice: cTokenInfo.config.chainlinkOracleConfig.fixedPrice
        });

        try oracle.addConfig(loadConfig) {
            console.log("Config added to oracle");
        } catch (bytes memory reason) {
            console.logBytes(reason);
        }

        // 4. Set reserve factor
        CToken(cTokenAddress)._setReserveFactor(cTokenInfo.config.reserveFactor);
        console.log("Reserve factor set: %s", cTokenInfo.config.reserveFactor);

        vm.stopBroadcast();
        console.log("cToken configuration complete!");
    }
} 