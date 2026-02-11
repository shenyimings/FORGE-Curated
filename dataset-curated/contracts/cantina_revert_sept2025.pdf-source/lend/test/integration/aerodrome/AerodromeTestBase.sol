// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./mocks/MockAerodromePositionManager.sol";
import "./mocks/MockAerodromeFactory.sol";
import "./mocks/MockGauge.sol";
import "./mocks/MockPool.sol";

import "../../../src/V3Vault.sol";
import "../../../src/V3Oracle.sol";
import "../../../src/GaugeManager.sol";
import "../../../src/utils/AerodromeHelper.sol";
import "../../../src/utils/Constants.sol";
import "../../../lib/AggregatorV3Interface.sol";

// Mock tokens
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10**decimals_);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock WETH
contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}
}

// Mock interest rate model
contract MockInterestRateModel is IInterestRateModel {
    uint256 constant Q96 = 2**96;
    
    function getUtilizationRateX96(uint256 debt, uint256 lent) external pure returns (uint256) {
        if (lent == 0) return 0;
        return debt * Q96 / lent;
    }

    function getRatesPerSecondX96(uint256 debt, uint256 lent) external pure returns (uint256, uint256) {
        uint256 utilization = debt * Q96 / (lent + 1);
        uint256 borrowRate = utilization / 100; // 1% per second at full utilization
        uint256 supplyRate = borrowRate * 9 / 10; // 90% of borrow rate
        return (borrowRate, supplyRate);
    }
    
    function getRatesPerSecondX64(uint256 cash, uint256 debt) external pure returns (uint256, uint256) {
        // Mock implementation using X64 precision
        uint256 Q64 = 2**64;
        uint256 utilization = debt * Q64 / (cash + debt + 1);
        uint256 borrowRate = utilization / 100;
        uint256 supplyRate = borrowRate * 9 / 10;
        return (borrowRate, supplyRate);
    }
}

// Mock Chainlink aggregator
contract MockChainlinkAggregator {
    int256 public price;
    uint8 public decimals;
    
    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

abstract contract AerodromeTestBase is Test, Constants {
    // Constants are inherited from Constants contract
    
    // Core contracts
    MockAerodromePositionManager public npm;
    MockAerodromeFactory public factory;
    V3Vault public vault;
    V3Oracle public oracle;
    GaugeManager public gaugeManager;
    
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public aero;
    MockWETH public weth;
    
    // Mock pools and gauges
    address public usdcDaiPool;
    address public wethUsdcPool;
    MockGauge public usdcDaiGauge;
    MockGauge public wethUsdcGauge;
    
    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public admin = address(0x3);
    
    // Mock contracts
    MockInterestRateModel public irm;
    MockChainlinkAggregator public usdcFeed;
    MockChainlinkAggregator public daiFeed;
    MockChainlinkAggregator public ethFeed;
    
    function setUp() public virtual {
        // Deploy mocks
        factory = new MockAerodromeFactory();
        npm = new MockAerodromePositionManager(address(factory), address(0));
        
        // Deploy tokens with proper decimals
        usdc = new MockERC20("USD Coin", "USDC", 6);  // 6 decimals for USDC
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);  // 18 decimals for DAI
        aero = new MockERC20("Aerodrome", "AERO", 18);  // 18 decimals for AERO
        weth = new MockWETH();  // WETH already has 18 decimals
        
        // Deploy mock pools - order tokens correctly
        if (address(usdc) < address(dai)) {
            usdcDaiPool = address(new MockPool(address(usdc), address(dai), 1, 1));
        } else {
            usdcDaiPool = address(new MockPool(address(dai), address(usdc), 1, 1));
        }
        
        // For WETH/USDC pair - order tokens correctly  
        if (address(weth) < address(usdc)) {
            wethUsdcPool = address(new MockPool(address(weth), address(usdc), 10, 10));
        } else {
            wethUsdcPool = address(new MockPool(address(usdc), address(weth), 10, 10));
        }
        
        // Set pools in factory - always use sorted order (token0 < token1)
        if (address(usdc) < address(dai)) {
            factory.setPool(address(usdc), address(dai), 1, usdcDaiPool);
        } else {
            factory.setPool(address(dai), address(usdc), 1, usdcDaiPool);
        }
        
        if (address(weth) < address(usdc)) {
            factory.setPool(address(weth), address(usdc), 10, wethUsdcPool);
        } else {
            factory.setPool(address(usdc), address(weth), 10, wethUsdcPool);
        }
        
        // Deploy price feeds
        usdcFeed = new MockChainlinkAggregator(1e8, 8); // $1
        daiFeed = new MockChainlinkAggregator(1e8, 8); // $1
        ethFeed = new MockChainlinkAggregator(2000e8, 8); // $2000
        
        // Deploy interest rate model
        irm = new MockInterestRateModel();
        
        // Deploy oracle
        oracle = new V3Oracle(npm, address(usdc), address(usdc));
        
        // Configure oracle
        oracle.setTokenConfig(
            address(usdc),
            AggregatorV3Interface(address(usdcFeed)),
            3600,
            IAerodromeSlipstreamPool(usdcDaiPool),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            type(uint16).max  // Set to max to bypass price checks in tests
        );
        oracle.setTokenConfig(
            address(dai),
            AggregatorV3Interface(address(daiFeed)),
            3600,
            IAerodromeSlipstreamPool(usdcDaiPool),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            type(uint16).max  // Set to max to bypass price checks in tests
        );
        oracle.setTokenConfig(
            address(weth),
            AggregatorV3Interface(address(ethFeed)),
            3600,
            IAerodromeSlipstreamPool(wethUsdcPool),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            type(uint16).max  // Set to max to bypass price checks in tests
        );
        
        // Deploy vault
        vault = new V3Vault(
            "Revert Lend USDC",
            "rlUSDC",
            address(usdc),
            npm,
            irm,
            oracle,
            IPermit2(address(0))
        );
        
        // Deploy gauge manager
        gaugeManager = new GaugeManager(
            IAerodromeNonfungiblePositionManager(address(npm)),
            IERC20(address(aero)),
            IVault(address(vault)),
            address(0), // universal router not needed in tests
            address(0), // permit2 not needed in tests
            admin       // feeWithdrawer - set to admin for tests
        );
        
        // Deploy gauges
        usdcDaiGauge = new MockGauge(address(aero), address(npm));
        wethUsdcGauge = new MockGauge(address(aero), address(npm));
        
        // Configure gauge manager
        gaugeManager.setGauge(usdcDaiPool, address(usdcDaiGauge));
        gaugeManager.setGauge(wethUsdcPool, address(wethUsdcGauge));
        
        // Set gauge manager in vault
        vault.setGaugeManager(address(gaugeManager));
        
        // Configure vault collateral factors
        vault.setTokenConfig(address(usdc), 9000, 100000); // 90% CF, higher collateral value limit
        vault.setTokenConfig(address(dai), 9000, 100000); // 90% CF, higher collateral value limit
        vault.setTokenConfig(address(weth), 8500, 100000); // 85% CF, higher collateral value limit
        
        // Fund test users
        usdc.mint(alice, 100000e6);  // 100,000 USDC with 6 decimals
        usdc.mint(bob, 100000e6);    // 100,000 USDC with 6 decimals
        dai.mint(alice, 100000e18);
        dai.mint(bob, 100000e18);
        deal(address(weth), alice, 100 ether);
        deal(address(weth), bob, 100 ether);
        
        // Fund gauges with AERO rewards
        aero.mint(address(usdcDaiGauge), 1000000e18);
        aero.mint(address(wethUsdcGauge), 1000000e18);
        
        // Labels
        vm.label(address(npm), "PositionManager");
        vm.label(address(factory), "Factory");
        vm.label(address(vault), "Vault");
        vm.label(address(oracle), "Oracle");
        vm.label(address(gaugeManager), "GaugeManager");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(address(weth), "WETH");
        vm.label(address(aero), "AERO");
    }
    
    // Helper function to create a position
    function createPosition(
        address owner,
        address token0,
        address token1,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 tokenId) {
        tokenId = uint256(keccak256(abi.encodePacked(owner, token0, token1, block.timestamp)));
        
        npm.mint(owner, tokenId);
        npm.setPosition(tokenId, token0, token1, tickSpacing, tickLower, tickUpper, liquidity);
        
        // Add some tokens owed to give the position value
        npm.setTokensOwed(tokenId, 100e6, 100e18); // 100 USDC and 100 DAI
        
        return tokenId;
    }
    
    // Helper function to create a position with proper token amounts
    function createPositionProper(
        address owner,
        address tokenA,
        address tokenB,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint128 amountA,
        uint128 amountB
    ) internal returns (uint256 tokenId) {
        tokenId = uint256(keccak256(abi.encodePacked(owner, tokenA, tokenB, block.timestamp)));
        
        npm.mint(owner, tokenId);
        npm.setPosition(tokenId, tokenA, tokenB, tickSpacing, tickLower, tickUpper, liquidity);
        
        // Determine token ordering (lower address is token0)
        if (tokenA < tokenB) {
            npm.setTokensOwed(tokenId, amountA, amountB);
        } else {
            npm.setTokensOwed(tokenId, amountB, amountA);
        }
        
        return tokenId;
    }
    
    // Helper to calculate fee from tick spacing
    // No conversion needed - Aerodrome uses tickSpacing directly
    // The tickSpacing is immutable for a pool and stored directly in positions
}