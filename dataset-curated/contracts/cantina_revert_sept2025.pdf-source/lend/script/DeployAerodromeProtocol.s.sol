// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/V3Oracle.sol";
import "../src/V3Vault.sol";
import "../src/InterestRateModel.sol";
import "../src/GaugeManager.sol";
import "../src/transformers/LeverageTransformer.sol";
import "../src/transformers/AutoCompound.sol";

contract DeployAerodromeProtocol is Script {
    // Constants
    uint256 constant Q64 = 2 ** 64;
    uint256 constant Q32 = 2 ** 32;
    
    // Base Mainnet Addresses
    address constant AERODROME_NPM = 0x827922686190790b37229fd06084350E74485b72;
    address constant AERODROME_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address constant AERODROME_GAUGE_FACTORY = 0xD30677bd8dd15132F251Cb54CbDA552d2A05Fb08;
    
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    
    address payable constant V3_UTILS = payable(0x7D1F9FC22beD0798cDA3Fdb18b14a96fc838B9E1);
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant ZEROX_ALLOWANCE_HOLDER = 0x0000000000001fF3684f28c67538d4D072C22734;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // Chainlink Feeds on Base
    address constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant CHAINLINK_BTC_USD = 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;
    address constant CHAINLINK_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    
    // Aerodrome Pool Addresses
    address constant WETH_USDC_POOL = 0xb2cc224c1c9feE385f8ad6a55b4d94E92359DC59;
    address constant CBBTC_USDC_POOL = 0x4e962BB3889Bf030368F56810A9c96B83CB3E778;

    // Deployed contract storage
    V3Oracle public oracle;
    InterestRateModel public irm;
    V3Vault public vault;
    GaugeManager public gaugeManager;
    LeverageTransformer public leverageTransformer;
    AutoCompound public autoCompound;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("==========================================");
        console.log("AERODROME PROTOCOL DEPLOYMENT - BASE");
        console.log("==========================================");
        console.log("Deployer:", deployer);
        console.log("");
        
        vm.startBroadcast();
        
        // 1. Deploy V3Oracle
        console.log("1. Deploying V3Oracle...");
        oracle = new V3Oracle(
            IAerodromeNonfungiblePositionManager(AERODROME_NPM),
            USDC,
            address(0) // feedRegistry not used on Base
        );
        console.log("   V3Oracle deployed:", address(oracle));
        
        // 2. Deploy InterestRateModel
        console.log("\n2. Deploying InterestRateModel...");
        irm = new InterestRateModel(
            0,                    // Base rate (0%)
            Q64 * 15 / 1000,     // Multiplier (1.5%)
            Q64 * 1,             // Jump multiplier (100%)
            Q64 * 80 / 100       // Kink (80%)
        );
        console.log("   InterestRateModel deployed:", address(irm));
        
        // 3. Deploy V3Vault
        console.log("\n3. Deploying V3Vault...");
        vault = new V3Vault(
            "Revert Lend USDC",
            "rlUSDC",
            USDC,
            IAerodromeNonfungiblePositionManager(AERODROME_NPM),
            irm,
            oracle,
            IPermit2(PERMIT2)
        );
        console.log("   V3Vault deployed:", address(vault));
        
        // 4. Deploy GaugeManager
        console.log("\n4. Deploying GaugeManager...");
        gaugeManager = new GaugeManager(
            IAerodromeNonfungiblePositionManager(AERODROME_NPM),
            IERC20(AERO),
            IVault(address(vault)),
            UNIVERSAL_ROUTER,
            ZEROX_ALLOWANCE_HOLDER,
            deployer // feeWithdrawer - set to deployer initially
        );
        console.log("   GaugeManager deployed:", address(gaugeManager));
        console.log("   - Includes swapAndIncreaseStakedPosition for deposits to staked positions");
        console.log("   - Includes migrateToVault for seamless migration from staking to borrowing");
        
        // Configure V3Utils in GaugeManager
        gaugeManager.setV3Utils(V3_UTILS);
        console.log("   - V3Utils configured in GaugeManager");
        
        // 5. Deploy LeverageTransformer
        console.log("\n5. Deploying LeverageTransformer...");
        leverageTransformer = new LeverageTransformer(
            INonfungiblePositionManager(AERODROME_NPM),
            UNIVERSAL_ROUTER,
            ZEROX_ALLOWANCE_HOLDER
        );
        console.log("   LeverageTransformer deployed:", address(leverageTransformer));
        
        // 6. Deploy AutoCompound
        console.log("\n6. Deploying AutoCompound...");
        autoCompound = new AutoCompound(
            INonfungiblePositionManager(AERODROME_NPM),
            deployer,  // operator - set to deployer initially
            deployer,  // withdrawer - set to deployer initially  
            60,        // TWAPSeconds
            200,       // maxTWAPTickDifference
            AERO       // aeroToken
        );
        console.log("   AutoCompound deployed:", address(autoCompound));
        console.log("   - Automated compounding with configurable fees (0-5%)");
        console.log("   - Supports AERO reward compounding");
        
        // Configure GaugeManager in AutoCompound
        autoCompound.setGaugeManager(address(gaugeManager), true);
        console.log("   - GaugeManager configured in AutoCompound");
        
        // 7. Configure Oracle
        console.log("\n7. Configuring Oracle...");
        
        // Set max pool price difference (2% tolerance)
        oracle.setMaxPoolPriceDifference(200);
        console.log("   Max pool price difference set to 2%");
        
        // USDC config
        oracle.setTokenConfig(
            USDC,
            AggregatorV3Interface(CHAINLINK_USDC_USD),
            86400,  // 24 hours for stablecoin feeds on L2
            IAerodromeSlipstreamPool(address(0)),
            60,
            V3Oracle.Mode.CHAINLINK,
            type(uint16).max
        );
        console.log("   USDC oracle configured (24h staleness)");
        
        // WETH config
        oracle.setTokenConfig(
            WETH,
            AggregatorV3Interface(CHAINLINK_ETH_USD),
            3600,
            IAerodromeSlipstreamPool(WETH_USDC_POOL),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            200
        );
        console.log("   WETH oracle configured");
        
        // cbBTC config (if pool exists)
        if (CBBTC_USDC_POOL != address(0)) {
            oracle.setTokenConfig(
                CBBTC,
                AggregatorV3Interface(CHAINLINK_BTC_USD),
                3600,
                IAerodromeSlipstreamPool(CBBTC_USDC_POOL),
                60,
                V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
                200
            );
            console.log("   cbBTC oracle configured");
        }
        
        // 8. Configure Vault
        console.log("\n8. Configuring Vault...");
        
        // Set gauge manager
        vault.setGaugeManager(address(gaugeManager));
        console.log("   Gauge manager set");
        
        // Enable transformers
        vault.setTransformer(V3_UTILS, true);
        vault.setTransformer(address(leverageTransformer), true);
        vault.setTransformer(address(autoCompound), true);
        console.log("   Transformers enabled (V3Utils, LeverageTransformer, AutoCompound)");
        
        // Configure vault in LeverageTransformer
        leverageTransformer.setVault(address(vault));
        console.log("   Vault configured in LeverageTransformer");
        
        // Set initial limits
        vault.setLimits(
            1e6,           // minLoanSize: 1 USDC
            10_000_000e6,  // globalLendLimit: 10M USDC
            8_000_000e6,   // globalDebtLimit: 8M USDC
            1_000_000e6,   // dailyLendIncreaseLimitMin: 1M USDC
            1_000_000e6    // dailyDebtIncreaseLimitMin: 1M USDC
        );
        console.log("   Vault limits set");
        
        // Set reserve factor
        vault.setReserveFactor(uint32(10 * Q32 / 100)); // 10%
        console.log("   Reserve factor set to 10%");
        
        // Set collateral factors for tokens
        console.log("\n9. Setting collateral factors...");
        vault.setTokenConfig(USDC, uint32(90 * Q32 / 100), type(uint32).max); // 90% CF
        console.log("   USDC collateral factor set to 90%");
        vault.setTokenConfig(WETH, uint32(85 * Q32 / 100), type(uint32).max); // 85% CF
        console.log("   WETH collateral factor set to 85%");
        vault.setTokenConfig(CBBTC, uint32(85 * Q32 / 100), type(uint32).max); // 85% CF
        console.log("   cbBTC collateral factor set to 85%");
        vault.setTokenConfig(AERO, uint32(75 * Q32 / 100), type(uint32).max); // 75% CF
        console.log("   AERO collateral factor set to 75%");
        
        vm.stopBroadcast();
        
        // Summary
        console.log("\n==========================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("==========================================");
        console.log("Oracle:", address(oracle));
        console.log("InterestRateModel:", address(irm));
        console.log("Vault:", address(vault));
        console.log("GaugeManager:", address(gaugeManager));
        console.log("LeverageTransformer:", address(leverageTransformer));
        console.log("AutoCompound:", address(autoCompound));
        console.log("V3Utils (existing):", V3_UTILS);
        console.log("\n==========================================");
        console.log("NEXT STEPS:");
        console.log("==========================================");
        console.log("1. Get gauge addresses for pools from Aerodrome");
        console.log("2. Run ConfigureGauges.s.sol to set pool->gauge mappings");
        console.log("3. Transfer ownership to multi-sig");
        console.log("4. Set emergency admin");
        console.log("5. Set compound fee percentage using setReward() on GaugeManager");
        console.log("\nNote: V3Utils is already configured in GaugeManager");
        console.log("If you need to update it later, use SetV3Utils.s.sol");
        console.log("\nTo find gauge addresses:");
        console.log("- Check Aerodrome UI for each pool");
        console.log("- Or call: GaugeFactory.gauges(poolAddress)");
        console.log("  at:", AERODROME_GAUGE_FACTORY);
    }
}
