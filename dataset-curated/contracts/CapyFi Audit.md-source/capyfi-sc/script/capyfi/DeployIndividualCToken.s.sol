// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { CErc20Delegator } from "../../src/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "../../src/contracts/CErc20Delegate.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { SimplePriceOracle } from "../../src/contracts/SimplePriceOracle.sol";
import { InterestRateModel } from "../../src/contracts/InterestRateModel.sol";
import { CToken } from "../../src/contracts/CToken.sol";
import { Config } from "./config/Config.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../HelperConfig.s.sol";

/**
 * @title DeployIndividualCToken
 * @notice This script deploys a single CErc20Delegator token based on the provided token symbol
 * @dev It uses the ENV variable TOKEN_SYMBOL to determine which token to deploy
 * After deployment, it also configures the token in the Comptroller
 */
contract DeployIndividualCToken is Script {
    address public deployedCTokenAddress;

    function run(address account) external returns (address) {
        // Get token symbol from environment variable
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        console.log("Deploying c%s token with account: %s", tokenSymbol, account);

        Config config;
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        console.log("Protocol Contracts");
        console.log("=================");
        console.log("Unitroller: %s", networkConfig.unitroller);
        console.log("Comptroller: %s", networkConfig.comptroller);
        console.log("Oracle: %s", networkConfig.oracle);
        console.log("");

        // Select appropriate config based on network
        config = helperConfig.getConfigBasedOnNetwork();

        Config.CTokenInfo[] memory configCtokens = config.getCTokens();
        vm.startBroadcast(account);

        // Convert token symbol to bytes32 for comparison
        bytes32 tokenSymbolBytes = keccak256(abi.encodePacked(tokenSymbol));

        // Create token symbol with 'ca' prefix
        string memory cTokenSymbol = string(abi.encodePacked("ca", tokenSymbol));

        for (uint256 i = 0; i < configCtokens.length; i++) {
            Config.CTokenInfo memory c = configCtokens[i];

            if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked(cTokenSymbol))) {
                console.log("Found config for: %s", cTokenSymbol);

                // Set the necessary parameters based on token symbol
                if (tokenSymbolBytes == keccak256(abi.encodePacked("UXD"))) {
                    c.args.underlying = networkConfig.underlyingTokens.uxd;
                    c.args.interestRateModel = networkConfig.interestRateModels.iRM_UXD_Updateable;
                } else if (tokenSymbolBytes == keccak256(abi.encodePacked("WETH"))) {
                    c.args.underlying = networkConfig.underlyingTokens.weth;
                    c.args.interestRateModel = networkConfig.interestRateModels.iRM_WETH_Updateable;
                } else if (tokenSymbolBytes == keccak256(abi.encodePacked("WBTC"))) {
                    c.args.underlying = networkConfig.underlyingTokens.wbtc;
                    c.args.interestRateModel = networkConfig.interestRateModels.iRM_WBTC_Updateable;
                } else if (tokenSymbolBytes == keccak256(abi.encodePacked("USDT"))) {
                    c.args.underlying = networkConfig.underlyingTokens.usdt;
                    c.args.interestRateModel = networkConfig.interestRateModels.iRM_USDT_Updateable;
                } else if (tokenSymbolBytes == keccak256(abi.encodePacked("USDC"))) {
                    c.args.underlying = networkConfig.underlyingTokens.usdc;
                    c.args.interestRateModel = networkConfig.interestRateModels.iRM_USDC_Updateable;
                } else if (tokenSymbolBytes == keccak256(abi.encodePacked("LAC"))) {
                    c.args.underlying = networkConfig.underlyingTokens.lac;
                    c.args.interestRateModel = networkConfig.interestRateModels.iRM_LAC_Updateable;
                } else {
                    revert(string(abi.encodePacked("Unsupported token symbol: ", tokenSymbol)));
                }

                // Set common parameters
                c.args.unitroller = networkConfig.unitroller;
                c.args.admin = account;

                console.log("Deploying %s with parameters:", cTokenSymbol);
                console.log("Underlying: %s", c.args.underlying);
                console.log("Interest Rate Model: %s", c.args.interestRateModel);
                console.log("Initial Exchange Rate: %s", c.args.initialExchangeRateMantissa);

                // Deploy CErc20Delegate implementation
                address implementation = address(new CErc20Delegate());
                
                // Deploy CErc20Delegator proxy
                CErc20Delegator cErc20Delegator = new CErc20Delegator(
                    c.args.underlying,
                    Comptroller(c.args.unitroller),
                    InterestRateModel(c.args.interestRateModel),
                    c.args.initialExchangeRateMantissa,
                    c.args.name,
                    c.args.symbol,
                    c.args.decimals,
                    payable(c.args.admin),
                    implementation,
                    ""
                );
                
                deployedCTokenAddress = address(cErc20Delegator);
                console.log("Deployed %s at: %s", cTokenSymbol, deployedCTokenAddress);
                
                // Note about configuration
                console.log("");
                console.log("NOTE: cToken deployed but not yet configured.");
                console.log("To configure the cToken, run:");
                console.log("make configure-ctoken CTOKEN_ADDRESS=%s ARGS=\"--network [network]\"", deployedCTokenAddress);
                
                break;
            }
        }

        require(deployedCTokenAddress != address(0), "Failed to deploy cToken");
        
        vm.stopBroadcast();
        return deployedCTokenAddress;
    }
}
