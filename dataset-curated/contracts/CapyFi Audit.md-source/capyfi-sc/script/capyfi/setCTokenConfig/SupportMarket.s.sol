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
 * @title SupportMarket
 * @notice Supports a cToken market in the Comptroller
 * @dev To be used for adding a cToken to the protocol
 */
contract SupportMarket is Script {
    error TokenNotFound(string tokenSymbol);
    
    function run(address account, string memory tokenSymbol) external {
        console.log("Supporting market in Comptroller for token: %s", tokenSymbol);
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
        
        vm.startBroadcast(account);

        // Support market in Comptroller
        Comptroller comptroller = Comptroller(unitrollerAddress);
        comptroller._supportMarket(CToken(cTokenAddress));
        
        vm.stopBroadcast();
        console.log("Market successfully supported in Comptroller for %s!", tokenSymbol);
    }
} 