// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Comptroller } from "../../../src/contracts/Comptroller.sol";
import { CToken } from "../../../src/contracts/CToken.sol";
import { CompoundLens } from "../../../src/contracts/Lens/CompoundLens.sol";
import { PriceOracle } from "../../../src/contracts/PriceOracle.sol";
import { EIP20Interface } from "../../../src/contracts/EIP20Interface.sol";
import { CErc20 } from "../../../src/contracts/CErc20.sol";
import { HelperConfig } from "../../HelperConfig.s.sol";

/**
 * @title QueryDeploymentState
 * @notice Script to query the current state of the Capyfi deployment using CompoundLens
 * @dev This script provides a snapshot of all cToken configurations and states
 */
contract QueryDeploymentState is Script {
    function run(address compoundLensAddress) external {
        console.log("\n==================================================");
        console.log("          CAPYFI PROTOCOL DEPLOYMENT STATE          ");
        console.log("==================================================\n");

        // Get the Comptroller address
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        // Get the unitroller from config or from token
        address unitrollerAddress = networkConfig.unitroller;
    
        // Deploy CompoundLens 
        // vm.startBroadcast(account);
        // CompoundLens lens = new CompoundLens();s
        // vm.stopBroadcast();

        // set compount lens from deployed address
        CompoundLens lens = CompoundLens(compoundLensAddress); // mainnet ethereum 
        // CompoundLens lens = CompoundLens(0xCec7aa3C3f724f03E42AE095C5A294c7194c23e2); // lachain
        
        // Get the Comptroller
        Comptroller comptroller = Comptroller(unitrollerAddress);
        
        // Get all markets (cTokens)
        CToken[] memory allMarkets = comptroller.getAllMarkets();
        
        // Get the price oracle
        PriceOracle priceOracle = comptroller.oracle();
        
        // Print core contracts information
        console.log("=== CORE CONTRACTS ===");
        console.log("Unitroller:  ", unitrollerAddress);
        console.log("Comptroller: ", address(comptroller.comptrollerImplementation()));
        console.log("Oracle:      ", address(priceOracle));
        console.log("Total Markets:", allMarkets.length);
        console.log("Close Factor:", formatMantissa(comptroller.closeFactorMantissa()), "%");
        
        // Special case for liquidation incentive - subtract 1.0 to show as premium percentage
        uint liquidationIncentive = comptroller.liquidationIncentiveMantissa();
        uint premiumPercentage = (liquidationIncentive * 10000) / 1e18;
        uint whole = premiumPercentage / 100;
        uint fraction = premiumPercentage % 100;
        string memory premium;
        
        if (fraction == 0) {
            premium = vm.toString(whole);
        } else if (fraction % 10 == 0) {
            premium = string(abi.encodePacked(vm.toString(whole), ".", vm.toString(fraction / 10)));
        } else {
            premium = string(abi.encodePacked(vm.toString(whole), ".", vm.toString(fraction)));
        }
        
        console.log("Liquidation Incentive:", premium, "%");
        console.log("==================================================\n");
        
        // Query each cToken's metadata
        for (uint i = 0; i < allMarkets.length; i++) {
            CToken cToken = allMarkets[i];
            
            // Get cToken metadata
            CompoundLens.CTokenMetadata memory metadata = lens.cTokenMetadata(cToken);
            
            // Get underlying price
            uint underlyingPrice = priceOracle.getUnderlyingPrice(cToken);
            
            // Print cToken details
            console.log(string(abi.encodePacked(
                "=== MARKET ", vm.toString(i + 1), ": ", cToken.symbol(), " ==="
            )));
            console.log("--------------------------------------------------------");
            
            // Market details
            console.log("cToken Address: ", address(cToken));
           
            // Interest rate model
            address interestRateModel = address(cToken.interestRateModel());
            console.log("Interest Rate Model: ", interestRateModel);
            
            // Get underlying token info if not caETH
            string memory symbol = cToken.symbol();

            if (keccak256(abi.encodePacked(symbol)) != keccak256(abi.encodePacked("caETH"))) {
                CErc20 cErc20 = CErc20(address(cToken));
                address underlying = cErc20.underlying();
                EIP20Interface token = EIP20Interface(underlying);
                console.log("Underlying Token: ", underlying);
                console.log("Token Symbol:     ", token.symbol());
                console.log("Token Decimals:   ", metadata.underlyingDecimals);
            } else {
                console.log("Underlying Token: ETH");
                console.log("Token Symbol:     ETH");
                console.log("Token Decimals:   18");
            }
            
            // Configuration parameters
            console.log("\nConfiguration Parameters:");
            console.log("- Listed:           ", metadata.isListed ? "Yes" : "No");
            console.log("- Collateral Factor:", formatMantissa(metadata.collateralFactorMantissa), "%");
            console.log("- Reserve Factor:   ", formatMantissa(metadata.reserveFactorMantissa), "%");
            console.log("- Exchange Rate:    ", metadata.exchangeRateCurrent, "(raw value)");
            
            // Market state
            console.log("\nMarket State:");
            console.log("- Supply Rate (APY):   ", formatRate(metadata.supplyRatePerBlock), "%");
            console.log("- Borrow Rate (APY):   ", formatRate(metadata.borrowRatePerBlock), "%");
            console.log("- Total Supply:       ", formatWithDecimals(metadata.totalSupply, metadata.cTokenDecimals), symbol);
            console.log("- Total Borrows:      ", formatWithDecimals(metadata.totalBorrows, metadata.underlyingDecimals), 
                keccak256(abi.encodePacked(symbol)) != keccak256(abi.encodePacked("caETH")) ? 
                    EIP20Interface(CErc20(address(cToken)).underlying()).symbol() : "ETH");
            console.log("- Total Reserves:     ", formatWithDecimals(metadata.totalReserves, metadata.underlyingDecimals), 
                keccak256(abi.encodePacked(symbol)) != keccak256(abi.encodePacked("caETH")) ? 
                    EIP20Interface(CErc20(address(cToken)).underlying()).symbol() : "ETH");
            console.log("- Total Cash:         ", formatWithDecimals(metadata.totalCash, metadata.underlyingDecimals), 
                keccak256(abi.encodePacked(symbol)) != keccak256(abi.encodePacked("caETH")) ? 
                    EIP20Interface(CErc20(address(cToken)).underlying()).symbol() : "ETH");
            
            // Price info
            console.log("\nPrice Information:");
            console.log("- Underlying Price: $", formatPrice(underlyingPrice, metadata.underlyingDecimals));
            
            // Borrow cap
            console.log("\nBorrow Cap:");
            if (metadata.borrowCap != type(uint).max && metadata.borrowCap > 0) {
                console.log("- Borrow Cap: ", formatWithDecimals(metadata.borrowCap, metadata.underlyingDecimals), 
                    keccak256(abi.encodePacked(symbol)) != keccak256(abi.encodePacked("caETH")) ? 
                        EIP20Interface(CErc20(address(cToken)).underlying()).symbol() : "ETH");
            } else {
                console.log("- Borrow Cap: Unlimited");
            }
            
            // COMP speeds if applicable
            if (metadata.compSupplySpeed > 0 || metadata.compBorrowSpeed > 0) {
                console.log("\nRewards:");
                console.log("- COMP Supply Speed: ", metadata.compSupplySpeed);
                console.log("- COMP Borrow Speed: ", metadata.compBorrowSpeed);
            }
            
            console.log("==================================================\n");
        }
    }
    
    // Helper functions for formatting output
    
    function formatMantissa(uint mantissa) internal pure returns (string memory) {
        // Convert mantissa to percentage with 2 decimal places
        // 0.5e18 should display as "50"
        // 1.08e18 should display as "108" (liquidation incentive is 1.08, not 0.08)
        // 0.075e18 should display as "7.5"
        
        uint percentValue = (mantissa * 10000) / 1e18; // Get 4 decimal places
        uint whole = percentValue / 100;
        uint fraction = percentValue % 100;
        
        if (fraction == 0) {
            return vm.toString(whole);
        } else if (fraction % 10 == 0) {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(fraction / 10)));
        } else {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(fraction)));
        }
    }
    
    function formatRate(uint ratePerBlock) internal pure returns (string memory) {
        uint blocksPerDay = 24 * 60 * 60 / 15; // 5760 blocks per day (15 sec per block)    
        uint daysPerYear = 365;
        
        // APY = (1 + (ratePerBlock / 1e18) * blocksPerDay) ^ 365 - 1
        // Using simplified calculation that matches the expected values
        uint ratePerYear = (ratePerBlock * blocksPerDay * daysPerYear) / 1e14;
        
        // Format with 2 decimal places
        uint whole = ratePerYear / 100;
        uint fraction = ratePerYear % 100;
        
        if (fraction == 0) {
            return vm.toString(whole);
        } else if (fraction < 10) {
            return string(abi.encodePacked(vm.toString(whole), ".0", vm.toString(fraction)));
        } else {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(fraction)));
        }
    }
    
    function formatWithDecimals(uint amount, uint decimals) internal pure returns (string memory) {
        if (decimals == 0) return vm.toString(amount);
        
        uint divisor = 10 ** decimals;
        uint integerPart = amount / divisor;
        uint fractionalPart = amount % divisor;
        
        // Format with up to 4 decimal places
        uint displayDecimals = decimals > 4 ? 4 : decimals;
        uint displayDivisor = 10 ** (decimals - displayDecimals);
        fractionalPart = fractionalPart / displayDivisor;
        
        string memory fractionalStr = vm.toString(fractionalPart);
        
        // Pad with leading zeros
        while (bytes(fractionalStr).length < displayDecimals) {
            fractionalStr = string(abi.encodePacked("0", fractionalStr));
        }
        
        return string(abi.encodePacked(vm.toString(integerPart), ".", fractionalStr));
    }
    
    function formatPrice(uint price, uint decimals) internal pure returns (string memory) {
        // Price is scaled by 10^(36 - decimals)
        uint adjustedPrice = (price * 100) / (10 ** (36 - decimals));
        return string(abi.encodePacked(vm.toString(adjustedPrice / 100), ".", vm.toString(adjustedPrice % 100)));
    }
} 