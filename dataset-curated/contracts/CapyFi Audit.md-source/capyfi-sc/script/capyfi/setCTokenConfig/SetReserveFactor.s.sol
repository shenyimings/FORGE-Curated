// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CToken } from "../../../src/contracts/CToken.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../../HelperConfig.s.sol";
import { Config } from "../config/Config.sol";
import { ProdConfig } from "../config/ProdConfig.sol";
import { CustomConfig } from "../config/CustomConfig.sol";

/**
 * @title SetReserveFactor
 * @notice Sets the reserve factor for a cToken
 * @dev Reserve factor determines what portion of interest goes to reserves
 */
contract SetReserveFactor is Script {
    error TokenNotFound(string tokenSymbol);
    
    function run(address account, string memory tokenSymbol) external {
        console.log("Setting reserve factor for token: %s", tokenSymbol);
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
            console.log("Cannot set reserve factor without configuration");
            return;
        }

        console.log("Found reserve factor for %s: %s", tokenSymbol, cTokenInfo.config.reserveFactor);
        
        vm.startBroadcast(account);

        // Set reserve factor in cToken
        CToken(cTokenAddress)._setReserveFactor(cTokenInfo.config.reserveFactor);
        
        vm.stopBroadcast();
        console.log("Reserve factor successfully set for %s to %s!", tokenSymbol, cTokenInfo.config.reserveFactor);
    }
} 