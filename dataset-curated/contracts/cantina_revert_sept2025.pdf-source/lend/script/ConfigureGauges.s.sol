// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/GaugeManager.sol";
import "../src/V3Vault.sol";

contract ConfigureGauges is Script {
    // Deployed contract addresses (Latest deployment: 2025-09-06)
    address constant GAUGE_MANAGER = 0x3a9cB8c9b358eD3bC44A539B9Bb356Fe64b08559;
    address constant VAULT = 0xb4694159ef30Fa21bCC9D963C7FA3716b0821E38;
    
    // Pool addresses
    address constant WETH_USDC_POOL = 0xb2cc224c1c9feE385f8ad6a55b4d94E92359DC59;
    address constant CBBTC_USDC_POOL = 0x4e962BB3889Bf030368F56810A9c96B83CB3E778;
    
    // Gauge addresses from Aerodrome
    address constant WETH_USDC_GAUGE = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8;
    address constant CBBTC_USDC_GAUGE = 0x6399ed6725cC163D019aA64FF55b22149D7179A8;
    
    // Optional: Additional pool/gauge pairs
    // address constant AERO_USDC_POOL = address(0);
    // address constant AERO_USDC_GAUGE = address(0);
    
    function run() external {
        require(GAUGE_MANAGER != address(0), "Update GAUGE_MANAGER address");
        require(VAULT != address(0), "Update VAULT address");
        require(WETH_USDC_GAUGE != address(0), "Need WETH/USDC gauge address");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("==========================================");
        console.log("CONFIGURING GAUGE MAPPINGS");
        console.log("==========================================");
        console.log("Deployer:", deployer);
        console.log("GaugeManager:", GAUGE_MANAGER);
        console.log("");
        
        vm.startBroadcast();
        
        GaugeManager gaugeManager = GaugeManager(GAUGE_MANAGER);
        
        // Configure pool -> gauge mappings
        console.log("Setting gauge mappings...");
        
        // WETH/USDC
        if (WETH_USDC_GAUGE != address(0)) {
            gaugeManager.setGauge(WETH_USDC_POOL, WETH_USDC_GAUGE);
            console.log("  WETH/USDC pool -> gauge configured");
        }
        
        // cbBTC/USDC
        if (CBBTC_USDC_GAUGE != address(0)) {
            gaugeManager.setGauge(CBBTC_USDC_POOL, CBBTC_USDC_GAUGE);
            console.log("  cbBTC/USDC pool -> gauge configured");
        }
        
        // Add more pool/gauge pairs as needed
        // if (AERO_USDC_GAUGE != address(0)) {
        //     gaugeManager.setGauge(AERO_USDC_POOL, AERO_USDC_GAUGE);
        //     console.log("  AERO/USDC pool -> gauge configured");
        // }
        
        vm.stopBroadcast();
        
        // Verify configuration
        console.log("\n==========================================");
        console.log("VERIFICATION");
        console.log("==========================================");
        
        console.log("WETH/USDC gauge:", gaugeManager.poolToGauge(WETH_USDC_POOL));
        if (CBBTC_USDC_GAUGE != address(0)) {
            console.log("cbBTC/USDC gauge:", gaugeManager.poolToGauge(CBBTC_USDC_POOL));
        }
        
        console.log("\nConfiguration complete!");
        console.log("Users can now:");
        console.log("- Stake positions in configured gauges");
        console.log("- Migrate staked positions to vault for borrowing");
        console.log("- Add liquidity to staked positions");
        console.log("- Compound AERO rewards automatically");
    }
    
    // Helper function to find gauge addresses (call this off-chain)
    function findGaugeAddress(address pool) external view returns (address) {
        // This would interact with the gauge factory
        // For now, you need to get these addresses from Aerodrome UI or docs
        return address(0);
    }
}
