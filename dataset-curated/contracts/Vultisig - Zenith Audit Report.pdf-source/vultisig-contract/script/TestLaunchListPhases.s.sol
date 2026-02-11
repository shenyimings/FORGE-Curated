// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "../contracts/extensions/ERC20.sol";
import {LaunchList} from "../contracts/LaunchList.sol";

// Minimal Uniswap V3 interfaces
interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract TestLaunchListPhases is Script {
    // Constants
    address immutable TOKEN_ADDRESS;
    address immutable LAUNCH_LIST_ADDRESS;

    // Uniswap constants
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant UNISWAP_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    uint24 constant POOL_FEE = 3000;

    // Contract instances
    ERC20 token;
    LaunchList launchList;
    IUniswapV3Factory factory;
    INonfungiblePositionManager positionManager;
    ISwapRouter router;

    // Test addresses derived from mnemonic
    address[] users;
    string MNEMONIC;
    uint256 constant NUM_USERS = 6;
    address deployer;

    constructor() {
        // Load addresses from environment variables
        TOKEN_ADDRESS = vm.envAddress("TOKEN_ADDRESS");
        LAUNCH_LIST_ADDRESS = vm.envAddress("LAUNCH_LIST_ADDRESS");
        MNEMONIC = vm.envString("MNEMONIC");
    }

    function setUp() internal {
        // Initialize contract instances
        token = ERC20(TOKEN_ADDRESS);
        launchList = LaunchList(LAUNCH_LIST_ADDRESS);
        factory = IUniswapV3Factory(UNISWAP_FACTORY);
        positionManager = INonfungiblePositionManager(POSITION_MANAGER);
        router = ISwapRouter(SWAP_ROUTER);

        // Generate deterministic addresses from mnemonic
        for (uint32 i = 0; i < NUM_USERS; i++) {
            uint256 key = vm.deriveKey(MNEMONIC, i);
            users.push(vm.addr(key));
            // Fund with ETH for gas and operations
            vm.deal(users[i], 100 ether);
        }
    }

    function run() external {
        // Check if we're running in simulation mode
        bool isFork = vm.envBool("FORK_MODE");

        if (isFork) {
            vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        }

        setUp();

        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Execute test phases
        testPhase0_LaunchListOnly();
        testPhase1_LimitedPoolTrading();
        testPhase2_ExtendedPoolTrading();
        testPhase3_Public();

        vm.stopBroadcast();
    }

    function testPhase0_LaunchListOnly() internal {
        console2.log("Testing Phase 0: Launch List Only");

        // add owner to launch list
        launchList.launchListAddress(deployer);

        // Whitelist first 3 users
        for (uint256 i = 0; i < 3; i++) {
            launchList.launchListAddress(users[i]);
            // Send initial tokens to whitelisted users
            token.transfer(users[i], 1000000 * 1e18);
        }

        launchList.setPhase(LaunchList.Phase.LAUNCH_LIST_ONLY);

        // Log phase setup completion
        console2.log("Phase 0 setup complete - whitelisted users:", users[0], users[1], users[2]);
    }

    function testPhase1_LimitedPoolTrading() internal {
        console2.log("Testing Phase 1: Limited Pool Trading");

        // Setup Uniswap pool
        address pool = setupUniswapPool();

        // Whitelist pool and router
        launchList.launchListPool(address(router));
        launchList.setPhase(LaunchList.Phase.LIMITED_POOL_TRADING);

        console2.log("Phase 1 setup complete - Pool address:", pool);
    }

    function testPhase2_ExtendedPoolTrading() internal {
        console2.log("Testing Phase 2: Extended Pool Trading");

        launchList.setPhase(LaunchList.Phase.EXTENDED_POOL_TRADING);

        console2.log("Phase 2 setup complete");
    }

    function testPhase3_Public() internal {
        console2.log("Testing Phase 3: Public Trading");

        launchList.setPhase(LaunchList.Phase.PUBLIC);

        console2.log("Phase 3 setup complete");
    }

    // Helper function to setup Uniswap pool
    function setupUniswapPool() internal returns (address) {
        address token0 = address(token) < WETH ? address(token) : WETH;
        address token1 = address(token) < WETH ? WETH : address(token);

        // Create pool
        address pool = factory.createPool(token0, token1, POOL_FEE);

        // Add pool to launch pool list
        launchList.launchListPool(pool);

        // Calculate initial sqrt price and ticks
        // Initial price: $0.03 = 0.000015 WETH/token
        uint160 sqrtPriceX96 = 314619361974781713622810621; // sqrt(0.000015) * 2^96

        // Initialize pool with price
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        // Calculate ticks for $0.03 to $10 range
        // Using https://docs.uniswap.org/sdk/v3/reference/overview
        int24 tickLower = -110580; // Price = 0.000015 WETH/token ($0.03)
        int24 tickUpper = -52500; // Price = 0.005 WETH/token ($10)

        // Add initial liquidity
        uint256 tokenAmount = 24_000_000 * 1e18; // 24M tokens for initial liquidity
        uint256 wethAmount = 0; // Single sided, no WETH needed

        // Approve tokens
        token.approve(address(positionManager), tokenAmount);

        // Add single-sided liquidity
        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickLower: token0 == address(token) ? tickLower : -tickUpper,
                tickUpper: token0 == address(token) ? tickUpper : -tickLower,
                amount0Desired: token0 == address(token) ? tokenAmount : wethAmount,
                amount1Desired: token0 == address(token) ? wethAmount : tokenAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp + 300
            })
        );

        console2.log("Pool initialized with single-sided liquidity");
        console2.log("Token address:", address(token));
        console2.log("Pool address:", pool);
        console2.log("Initial price (in WETH):", "0.000015");
        console2.log("Price range: $0.03 - $10 (assuming $2000 ETH)");

        return pool;
    }
}
