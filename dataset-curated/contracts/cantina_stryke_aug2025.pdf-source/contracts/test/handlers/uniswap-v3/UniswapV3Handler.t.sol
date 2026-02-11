// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {UniswapV3Handler} from "../../../src/handlers/uniswap-v3/UniswapV3Handler.sol";
import {PositionManager} from "../../../src/PositionManager.sol";
import {UniswapV3FactoryDeployer} from "./uniswap-v3-utils/UniswapV3FactoryDeployer.sol";

import {UniswapV3PoolUtils} from "./uniswap-v3-utils/UniswapV3PoolUtils.sol";
import {UniswapV3LiquidityManagement} from "./uniswap-v3-utils/UniswapV3LiquidityManagement.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {IV3Pool} from "../../../src/interfaces/handlers/V3/IV3Pool.sol";
import {V3BaseHandler} from "../../../src/handlers/V3BaseHandler.sol";
import {IHandler} from "../../../src/interfaces/IHandler.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {Tick} from "@uniswap/v3-core/contracts/libraries/Tick.sol";

contract UniswapV3HandlerTest is Test, UniswapV3FactoryDeployer {
    using TickMath for int24;

    PositionManager public positionManager;
    UniswapV3Handler public handler;
    UniswapV3FactoryDeployer public factoryDeployer;
    IUniswapV3Factory public factory;

    UniswapV3PoolUtils public uniswapV3PoolUtils;
    UniswapV3LiquidityManagement public uniswapV3LiquidityManagement;

    MockERC20 public USDC; // token0
    MockERC20 public ETH; // token1

    MockERC20 public token0;
    MockERC20 public token1;

    address public feeReceiver = makeAddr("feeReceiver");

    address public owner = makeAddr("owner");

    IUniswapV3Pool public pool;

    function setUp() public {
        // Deploy the Uniswap V3 Factory
        factory = IUniswapV3Factory(deployUniswapV3Factory());

        uniswapV3PoolUtils = new UniswapV3PoolUtils();

        uniswapV3LiquidityManagement = new UniswapV3LiquidityManagement(address(factory));

        // Deploy mock tokens for testing
        USDC = new MockERC20("USD Coin", "USDC", 6);
        ETH = new MockERC20("Ethereum", "ETH", 18);

        vm.startPrank(owner);

        positionManager = new PositionManager(owner);

        // Deploy the Uniswap V3 handler with additional arguments
        handler = new UniswapV3Handler(
            feeReceiver, // _feeReceiver
            address(factory), // _factory
            0xa598dd2fba360510c5a8f02f44423a4468e902df5857dbce3ca162a43a3a31ff
        );
        // Whitelist the handler
        positionManager.updateWhitelistHandler(address(handler), true);

        handler.updateHandlerSettings(address(positionManager), true, address(0), 6 hours, feeReceiver);

        positionManager.updateWhitelistHandlerWithApp(address(handler), address(this), true);

        vm.stopPrank();

        // Initialize the pool with sqrtPriceX96 representing 1 ETH = 2000 USDC
        uint160 sqrtPriceX96 = 1771595571142957166518320255467520;
        pool = IUniswapV3Pool(uniswapV3PoolUtils.deployAndInitializePool(factory, ETH, USDC, 500, sqrtPriceX96));

        uniswapV3PoolUtils.addLiquidity(
            UniswapV3PoolUtils.AddLiquidityStruct({
                liquidityManager: address(uniswapV3LiquidityManagement),
                pool: pool,
                user: owner,
                desiredAmount0: 100000000e6,
                desiredAmount1: 100 ether,
                desiredTickLower: 200010,
                desiredTickUpper: 201010,
                requireMint: true
            })
        );
    }

    function testPoolDeployment() public {
        assertTrue(address(pool) != address(0), "Pool was not deployed");

        (address _token0, address _token1) =
            (ETH < USDC) ? (address(ETH), address(USDC)) : (address(USDC), address(ETH));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        assertEq(pool.token0(), address(USDC), "Token0 is not USDC");
        assertEq(pool.token1(), address(ETH), "Token1 is not ETH");
    }

    struct TestVars {
        uint160 sqrtPriceX96;
        int24 currentTick;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 tokenId;
        uint256 sharesMinted;
        BalanceCheckVars balanceBefore;
        BalanceCheckVars balanceAfter;
    }

    struct TokenIdInfo {
        uint128 totalLiquidity;
        uint128 liquidityUsed;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint128 reservedLiquidity;
    }

    struct BalanceCheckVars {
        uint256 balance0;
        uint256 balance1;
    }

    struct LiquidityCheckVars {
        uint128 liquidity0;
        uint128 liquidity1;
    }

    function testMintPositionWithOnlyUSDC() public {
        TestVars memory vars;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        uint256 amount1Desired = 0; // No ETH

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing; // 1 tick spaces wide

        vm.startPrank(owner);
        USDC.mint(owner, amount0Desired);
        USDC.approve(address(positionManager), amount0Desired);
        vars.balanceBefore.balance0 = USDC.balanceOf(owner);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(params, ""));
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        TokenIdInfo memory info;
        (
            info.totalLiquidity,
            info.liquidityUsed,
            info.feeGrowthInside0LastX128,
            info.feeGrowthInside1LastX128,
            info.tokensOwed0,
            info.tokensOwed1,
            ,
            ,
            ,
            info.reservedLiquidity
        ) = handler.tokenIds(vars.tokenId);

        assertTrue(info.totalLiquidity > 0, "Total liquidity should be greater than 0");
        assertEq(info.liquidityUsed, 0, "Liquidity used should be 0");
        assertEq(info.feeGrowthInside0LastX128, 0, "Initial feeGrowthInside0LastX128 should be 0");
        assertEq(info.feeGrowthInside1LastX128, 0, "Initial feeGrowthInside1LastX128 should be 0");
        assertEq(info.tokensOwed0, 0, "Initial tokensOwed0 should be 0");
        assertEq(info.tokensOwed1, 0, "Initial tokensOwed1 should be 0");
        assertEq(info.reservedLiquidity, 0, "Initial reserved liquidity should be 0");

        assertEq(
            handler.balanceOf(owner, vars.tokenId), vars.sharesMinted, "Owner's balance should equal shares minted"
        );

        vars.balanceAfter.balance0 = USDC.balanceOf(owner);
        assertTrue(vars.balanceAfter.balance0 < vars.balanceBefore.balance0, "USDC balance should have decreased");
        assertTrue(
            vars.balanceBefore.balance0 - vars.balanceAfter.balance0 <= amount0Desired,
            "USDC spent should not exceed desired amount"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        vm.stopPrank();
    }

    function testFuzzMintPositionWithOnlyUSDC(uint256 amount0Desired) public {
        TestVars memory vars;

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();

        // Calculate tick range
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 10 * tickSpacing; // 10 tick spaces wide

        // Calculate max liquidity per tick
        uint128 maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);

        // Set minimum amount to 1000 USDC (1000 * 10^6)
        uint256 minAmount0 = 1000 * 10 ** 6;

        // Calculate maximum amount for maxLiquidityPerTick
        uint256 maxAmount0 = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            maxLiquidityPerTick
        );

        // Ensure maxAmount0 is greater than minAmount0
        maxAmount0 = maxAmount0 > minAmount0 ? maxAmount0 : minAmount0 + 1;

        // Bound the fuzzed input to a reasonable range, starting from the minimum amount
        amount0Desired = bound(amount0Desired, minAmount0, maxAmount0);
        uint256 amount1Desired = 0; // No ETH

        vm.startPrank(owner);
        USDC.mint(owner, amount0Desired);
        USDC.approve(address(positionManager), amount0Desired);
        vars.balanceBefore.balance0 = USDC.balanceOf(owner);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(params, ""));
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        TokenIdInfo memory info;
        (
            info.totalLiquidity,
            info.liquidityUsed,
            info.feeGrowthInside0LastX128,
            info.feeGrowthInside1LastX128,
            info.tokensOwed0,
            info.tokensOwed1,
            ,
            ,
            ,
            info.reservedLiquidity
        ) = handler.tokenIds(vars.tokenId);

        assertTrue(info.totalLiquidity > 0, "Total liquidity should be greater than 0");
        assertEq(info.liquidityUsed, 0, "Liquidity used should be 0");
        assertEq(info.feeGrowthInside0LastX128, 0, "Initial feeGrowthInside0LastX128 should be 0");
        assertEq(info.feeGrowthInside1LastX128, 0, "Initial feeGrowthInside1LastX128 should be 0");
        assertEq(info.tokensOwed0, 0, "Initial tokensOwed0 should be 0");
        assertEq(info.tokensOwed1, 0, "Initial tokensOwed1 should be 0");
        assertEq(info.reservedLiquidity, 0, "Initial reserved liquidity should be 0");

        assertEq(
            handler.balanceOf(owner, vars.tokenId), vars.sharesMinted, "Owner's balance should equal shares minted"
        );

        vars.balanceAfter.balance0 = USDC.balanceOf(owner);
        assertTrue(vars.balanceAfter.balance0 < vars.balanceBefore.balance0, "USDC balance should have decreased");
        assertTrue(
            vars.balanceBefore.balance0 - vars.balanceAfter.balance0 <= amount0Desired,
            "USDC spent should not exceed desired amount"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        vm.stopPrank();
    }

    function testMintPositionWithOnlyETH() public {
        TestVars memory vars;
        uint256 amount1Desired = 1 ether; // 1 ETH
        uint256 amount0Desired = 0; // No USDC

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing; // 1 tick spaces wide

        vm.startPrank(owner);
        ETH.mint(owner, amount1Desired);
        ETH.approve(address(positionManager), amount1Desired);
        vars.balanceBefore.balance1 = ETH.balanceOf(owner);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(params, ""));
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        TokenIdInfo memory info;
        (
            info.totalLiquidity,
            info.liquidityUsed,
            info.feeGrowthInside0LastX128,
            info.feeGrowthInside1LastX128,
            info.tokensOwed0,
            info.tokensOwed1,
            ,
            ,
            ,
            info.reservedLiquidity
        ) = handler.tokenIds(vars.tokenId);

        assertTrue(info.totalLiquidity > 0, "Total liquidity should be greater than 0");
        assertEq(info.liquidityUsed, 0, "Liquidity used should be 0");
        assertEq(info.feeGrowthInside0LastX128, 0, "Initial feeGrowthInside0LastX128 should be 0");
        assertEq(info.feeGrowthInside1LastX128, 0, "Initial feeGrowthInside1LastX128 should be 0");
        assertEq(info.tokensOwed0, 0, "Initial tokensOwed0 should be 0");
        assertEq(info.tokensOwed1, 0, "Initial tokensOwed1 should be 0");
        assertEq(info.reservedLiquidity, 0, "Initial reserved liquidity should be 0");

        assertEq(
            handler.balanceOf(owner, vars.tokenId), vars.sharesMinted, "Owner's balance should equal shares minted"
        );

        vars.balanceAfter.balance1 = ETH.balanceOf(owner);
        assertTrue(vars.balanceAfter.balance1 < vars.balanceBefore.balance1, "ETH balance should have decreased");
        assertTrue(
            vars.balanceBefore.balance1 - vars.balanceAfter.balance1 <= amount1Desired,
            "ETH spent should not exceed desired amount"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        assertLt(vars.tickUpper, vars.currentTick, "Upper tick should be below current tick for ETH-only position");
        assertLt(vars.tickLower, vars.tickUpper, "Lower tick should be below upper tick");

        vm.stopPrank();
    }

    function testFuzzMintPositionWithOnlyETH(uint256 amount1Desired) public {
        TestVars memory vars;

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();

        // Calculate tick range
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 10 * tickSpacing; // 10 tick spaces wide

        // Calculate max liquidity per tick
        uint128 maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);

        // Set minimum amount to 1000 wei
        uint256 minAmount1 = 1000;

        // Calculate maximum amount for maxLiquidityPerTick
        uint256 maxAmount1 = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            maxLiquidityPerTick
        );

        // Ensure maxAmount1 is greater than minAmount1
        maxAmount1 = maxAmount1 > minAmount1 ? maxAmount1 : minAmount1 + 1;

        // Bound the fuzzed input to a reasonable range, starting from the minimum amount
        amount1Desired = bound(amount1Desired, minAmount1, maxAmount1);
        uint256 amount0Desired = 0; // No USDC

        vm.startPrank(owner);
        ETH.mint(owner, amount1Desired);
        ETH.approve(address(positionManager), amount1Desired);
        vars.balanceBefore.balance1 = ETH.balanceOf(owner);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(params, ""));
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        TokenIdInfo memory info;
        (
            info.totalLiquidity,
            info.liquidityUsed,
            info.feeGrowthInside0LastX128,
            info.feeGrowthInside1LastX128,
            info.tokensOwed0,
            info.tokensOwed1,
            ,
            ,
            ,
            info.reservedLiquidity
        ) = handler.tokenIds(vars.tokenId);

        assertTrue(info.totalLiquidity > 0, "Total liquidity should be greater than 0");
        assertEq(info.liquidityUsed, 0, "Liquidity used should be 0");
        assertEq(info.feeGrowthInside0LastX128, 0, "Initial feeGrowthInside0LastX128 should be 0");
        assertEq(info.feeGrowthInside1LastX128, 0, "Initial feeGrowthInside1LastX128 should be 0");
        assertEq(info.tokensOwed0, 0, "Initial tokensOwed0 should be 0");
        assertEq(info.tokensOwed1, 0, "Initial tokensOwed1 should be 0");
        assertEq(info.reservedLiquidity, 0, "Initial reserved liquidity should be 0");

        assertEq(
            handler.balanceOf(owner, vars.tokenId), vars.sharesMinted, "Owner's balance should equal shares minted"
        );

        vars.balanceAfter.balance1 = ETH.balanceOf(owner);
        assertTrue(vars.balanceAfter.balance1 < vars.balanceBefore.balance1, "ETH balance should have decreased");
        assertTrue(
            vars.balanceBefore.balance1 - vars.balanceAfter.balance1 <= amount1Desired,
            "ETH spent should not exceed desired amount"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        assertLt(vars.tickUpper, vars.currentTick, "Upper tick should be below current tick for ETH-only position");
        assertLt(vars.tickLower, vars.tickUpper, "Lower tick should be below upper tick");

        vm.stopPrank();
    }

    function testMintPositionInRange() public {
        TestVars memory vars;

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();

        // Calculate tick range that spans the current tick
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing; // 20 tick spaces wide

        // Set initial amounts (more than needed to ensure we hit the liquidity limit)
        uint256 amount0Desired = 10000 * 10 ** 6; // 10,000 USDC
        uint256 amount1Desired = 5 * 10 ** 18; // 5 ETH

        // Calculate liquidity for both amounts
        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtRatioAtTick(vars.tickLower), TickMath.getSqrtRatioAtTick(vars.tickUpper), amount0Desired
        );

        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(vars.tickLower), TickMath.getSqrtRatioAtTick(vars.tickUpper), amount1Desired
        );

        // Use the lesser of the two liquidities
        vars.liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

        // Calculate the exact amounts needed for this liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            vars.liquidity
        );

        vm.startPrank(owner);
        USDC.mint(owner, amount0);
        ETH.mint(owner, amount1);
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);
        vars.balanceBefore.balance0 = USDC.balanceOf(owner);
        vars.balanceBefore.balance1 = ETH.balanceOf(owner);

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(params, ""));
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        TokenIdInfo memory info;
        (
            info.totalLiquidity,
            info.liquidityUsed,
            info.feeGrowthInside0LastX128,
            info.feeGrowthInside1LastX128,
            info.tokensOwed0,
            info.tokensOwed1,
            ,
            ,
            ,
            info.reservedLiquidity
        ) = handler.tokenIds(vars.tokenId);

        // Check if the difference is within an acceptable range (e.g., 0.0001% or 1 in 1,000,000)
        uint256 liquidityDifference = info.totalLiquidity > vars.liquidity
            ? info.totalLiquidity - vars.liquidity
            : vars.liquidity - info.totalLiquidity;
        assertTrue(liquidityDifference * 1_000_000 <= vars.liquidity, "Liquidity difference exceeds acceptable range");

        assertEq(info.liquidityUsed, 0, "Liquidity used should be 0");
        assertEq(info.feeGrowthInside0LastX128, 0, "Initial feeGrowthInside0LastX128 should be 0");
        assertEq(info.feeGrowthInside1LastX128, 0, "Initial feeGrowthInside1LastX128 should be 0");
        assertEq(info.tokensOwed0, 0, "Initial tokensOwed0 should be 0");
        assertEq(info.tokensOwed1, 0, "Initial tokensOwed1 should be 0");
        assertEq(info.reservedLiquidity, 0, "Initial reserved liquidity should be 0");

        assertEq(
            handler.balanceOf(owner, vars.tokenId), vars.sharesMinted, "Owner's balance should equal shares minted"
        );

        vars.balanceAfter.balance0 = USDC.balanceOf(owner);
        vars.balanceAfter.balance1 = ETH.balanceOf(owner);
        assertEq(
            vars.balanceBefore.balance0 - vars.balanceAfter.balance0, amount0, "Exact amount of USDC should be spent"
        );
        assertEq(
            vars.balanceBefore.balance1 - vars.balanceAfter.balance1, amount1, "Exact amount of ETH should be spent"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        vm.stopPrank();
    }

    function testFuzzMintPositionInRange(uint256 amount0Desired, uint256 amount1Desired) public {
        TestVars memory vars;

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();

        // Calculate tick range that spans the current tick
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing; // 20 tick spaces wide

        // Ensure the position spans the current tick
        require(
            vars.tickLower < vars.currentTick && vars.currentTick < vars.tickUpper, "Position must span current tick"
        );

        // Bound the fuzzed inputs to reasonable ranges
        amount0Desired = bound(amount0Desired, 1_000_000, 1_000_000_000 * 10 ** 6);
        amount1Desired = bound(amount1Desired, 0.1 ether, 10000 ether);

        // Calculate liquidity for both amounts
        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtRatioAtTick(vars.tickLower), TickMath.getSqrtRatioAtTick(vars.tickUpper), amount0Desired
        );

        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(vars.tickLower), TickMath.getSqrtRatioAtTick(vars.tickUpper), amount1Desired
        );

        // Use the lesser of the two liquidities
        vars.liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

        // Calculate the exact amounts needed for this liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            vars.liquidity
        );

        vm.startPrank(owner);
        USDC.mint(owner, amount0);
        ETH.mint(owner, amount1);
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);
        vars.balanceBefore.balance0 = USDC.balanceOf(owner);
        vars.balanceBefore.balance1 = ETH.balanceOf(owner);

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(params, ""));
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        TokenIdInfo memory info;
        (
            info.totalLiquidity,
            info.liquidityUsed,
            info.feeGrowthInside0LastX128,
            info.feeGrowthInside1LastX128,
            info.tokensOwed0,
            info.tokensOwed1,
            ,
            ,
            ,
            info.reservedLiquidity
        ) = handler.tokenIds(vars.tokenId);

        // Check if the difference is within an acceptable range (e.g., 0.0001% or 1 in 1,000,000)
        uint256 liquidityDifference = info.totalLiquidity > vars.liquidity
            ? info.totalLiquidity - vars.liquidity
            : vars.liquidity - info.totalLiquidity;
        assertTrue(liquidityDifference * 100000 <= vars.liquidity, "Liquidity difference exceeds acceptable range");

        assertEq(info.liquidityUsed, 0, "Liquidity used should be 0");
        assertEq(info.feeGrowthInside0LastX128, 0, "Initial feeGrowthInside0LastX128 should be 0");
        assertEq(info.feeGrowthInside1LastX128, 0, "Initial feeGrowthInside1LastX128 should be 0");
        assertEq(info.tokensOwed0, 0, "Initial tokensOwed0 should be 0");
        assertEq(info.tokensOwed1, 0, "Initial tokensOwed1 should be 0");
        assertEq(info.reservedLiquidity, 0, "Initial reserved liquidity should be 0");

        assertEq(
            handler.balanceOf(owner, vars.tokenId), vars.sharesMinted, "Owner's balance should equal shares minted"
        );

        vars.balanceAfter.balance0 = USDC.balanceOf(owner);
        vars.balanceAfter.balance1 = ETH.balanceOf(owner);
        assertEq(
            vars.balanceBefore.balance0 - vars.balanceAfter.balance0, amount0, "Exact amount of USDC should be spent"
        );
        assertEq(
            vars.balanceBefore.balance1 - vars.balanceAfter.balance1, amount1, "Exact amount of ETH should be spent"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        vm.stopPrank();
    }

    function testBurnPositionWithOnlyUSDC() public {
        TestVars memory vars;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        uint256 amount1Desired = 0; // No ETH

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing; // 1 tick spaces wide

        vm.startPrank(owner);
        USDC.mint(owner, amount0Desired);
        USDC.approve(address(positionManager), amount0Desired);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory mintParams = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(mintParams, ""));
        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        // Burn the position
        uint256 sharesBurned = vars.sharesMinted / 2; // Burn half of the shares
        uint256 balanceBefore = USDC.balanceOf(owner);

        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesBurned)
        });

        bytes memory burnData = abi.encode(burnParams, "");
        positionManager.burnPosition(IHandler(address(handler)), burnData);

        uint256 balanceAfter = USDC.balanceOf(owner);
        assertTrue(balanceAfter > balanceBefore, "USDC balance should have increased after burning");

        vm.stopPrank();
    }

    function testBurnPositionWithOnlyETH() public {
        TestVars memory vars;
        uint256 amount1Desired = 1 ether; // 1 ETH
        uint256 amount0Desired = 0; // No USDC

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing; // 1 tick spaces wide

        vm.startPrank(owner);
        ETH.mint(owner, amount1Desired);
        ETH.approve(address(positionManager), amount1Desired);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory mintParams = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(mintParams, ""));
        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        // Burn the position
        uint256 sharesBurned = vars.sharesMinted / 2; // Burn half of the shares
        uint256 balanceBefore = ETH.balanceOf(owner);

        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesBurned)
        });

        bytes memory burnData = abi.encode(burnParams, "");
        positionManager.burnPosition(IHandler(address(handler)), burnData);

        uint256 balanceAfter = ETH.balanceOf(owner);
        assertTrue(balanceAfter > balanceBefore, "ETH balance should have increased after burning");

        vm.stopPrank();
    }

    function testBurnPositionInRange() public {
        TestVars memory vars;

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();

        // Calculate tick range that spans the current tick
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing; // 20 tick spaces wide

        // Set initial amounts (more than needed to ensure we hit the liquidity limit)
        uint256 amount0Desired = 10000 * 10 ** 6; // 10,000 USDC
        uint256 amount1Desired = 5 * 10 ** 18; // 5 ETH

        // Calculate liquidity for both amounts
        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtRatioAtTick(vars.tickLower), TickMath.getSqrtRatioAtTick(vars.tickUpper), amount0Desired
        );

        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(vars.tickLower), TickMath.getSqrtRatioAtTick(vars.tickUpper), amount1Desired
        );

        // Use the lesser of the two liquidities
        vars.liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

        // Calculate the exact amounts needed for this liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            vars.liquidity
        );

        vm.startPrank(owner);
        USDC.mint(owner, amount0);
        ETH.mint(owner, amount1);
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.MintPositionParams memory mintParams = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = positionManager.mintPosition(IHandler(address(handler)), abi.encode(mintParams, ""));
        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        // Burn half of the position
        uint256 sharesBurned = vars.sharesMinted / 2;
        uint256 balanceBefore0 = USDC.balanceOf(owner);
        uint256 balanceBefore1 = ETH.balanceOf(owner);

        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesBurned)
        });

        bytes memory burnData = abi.encode(burnParams, "");
        positionManager.burnPosition(IHandler(address(handler)), burnData);

        uint256 balanceAfter0 = USDC.balanceOf(owner);
        uint256 balanceAfter1 = ETH.balanceOf(owner);
        assertTrue(balanceAfter0 > balanceBefore0, "USDC balance should have increased after burning");
        assertTrue(balanceAfter1 > balanceBefore1, "ETH balance should have increased after burning");

        vm.stopPrank();
    }

    function testFuzzBurnPositionWithOnlyUSDC(uint256 burnPercentage) public {
        // First, mint a position
        testMintPositionWithOnlyUSDC();

        // Bound the burnPercentage between 1% and 100%
        burnPercentage = bound(burnPercentage, 1, 100);

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Calculate shares to burn based on the fuzzed percentage
        uint256 sharesBurned = (vars.sharesMinted * burnPercentage) / 100;
        uint256 balanceBefore = USDC.balanceOf(owner);

        vm.startPrank(owner);
        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesBurned)
        });

        bytes memory burnData = abi.encode(burnParams, "");
        positionManager.burnPosition(IHandler(address(handler)), burnData);

        uint256 balanceAfter = USDC.balanceOf(owner);
        assertTrue(balanceAfter > balanceBefore, "USDC balance should have increased after burning");

        vm.stopPrank();
    }

    function testFuzzBurnPositionWithOnlyETH(uint256 burnPercentage) public {
        // First, mint a position
        testMintPositionWithOnlyETH();

        // Bound the burnPercentage between 1% and 100%
        burnPercentage = bound(burnPercentage, 1, 100);

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Calculate shares to burn based on the fuzzed percentage
        uint256 sharesBurned = (vars.sharesMinted * burnPercentage) / 100;
        uint256 balanceBefore = ETH.balanceOf(owner);

        vm.startPrank(owner);
        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesBurned)
        });

        bytes memory burnData = abi.encode(burnParams, "");
        positionManager.burnPosition(IHandler(address(handler)), burnData);

        uint256 balanceAfter = ETH.balanceOf(owner);
        assertTrue(balanceAfter > balanceBefore, "ETH balance should have increased after burning");

        vm.stopPrank();
    }

    function testFuzzBurnPositionInRange(uint256 burnPercentage) public {
        // First, mint a position
        testMintPositionInRange();

        // Bound the burnPercentage between 1% and 100%
        burnPercentage = bound(burnPercentage, 1, 100);

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Calculate shares to burn based on the fuzzed percentage
        uint256 sharesBurned = (vars.sharesMinted * burnPercentage) / 100;
        uint256 balanceBefore0 = USDC.balanceOf(owner);
        uint256 balanceBefore1 = ETH.balanceOf(owner);

        vm.startPrank(owner);
        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesBurned)
        });

        bytes memory burnData = abi.encode(burnParams, "");
        positionManager.burnPosition(IHandler(address(handler)), burnData);

        uint256 balanceAfter0 = USDC.balanceOf(owner);
        uint256 balanceAfter1 = ETH.balanceOf(owner);
        assertTrue(balanceAfter0 > balanceBefore0, "USDC balance should have increased after burning");
        assertTrue(balanceAfter1 > balanceBefore1, "ETH balance should have increased after burning");

        vm.stopPrank();
    }

    function testUseAndUnusePositionWithOnlyUSDC() public {
        // First, run the testMintPositionWithOnlyUSDC test
        testMintPositionWithOnlyUSDC();

        // Now we can assume that a position has been minted
        // We need to retrieve the tokenId and sharesMinted from the previous test
        TestVars memory vars;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use position
        uint256 sharesToUse = vars.sharesMinted / 2; // Use half of the shares

        // Calculate the amount of tokens needed for the liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(sharesToUse)
        );

        // Give allowance from address(this) to positionManager for the calculated amounts
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(sharesToUse)
        });

        bytes memory useData = abi.encode(useParams, "");
        positionManager.usePosition(IHandler(address(handler)), useData);

        // Check if liquidity is used
        (, uint128 liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        assertEq(liquidityUsed, sharesToUse, "Liquidity used should match shares used");

        // Unuse position
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(sharesToUse)
        });

        bytes memory unuseData = abi.encode(unuseParams, "");
        positionManager.unusePosition(IHandler(address(handler)), unuseData);

        (, liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        (vars.balanceBefore.balance0, vars.balanceBefore.balance1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityUsed)
        );

        assertLt(vars.balanceBefore.balance0, 99999, "Dust amount of USDC should be less than 99999");
        assertLt(vars.balanceBefore.balance1, 100000000000, "Dust amount of ETH should be less than 99999");
    }

    function testUseAndUnusePositionWithOnlyETH() public {
        // First, run the testMintPositionWithOnlyETH test
        testMintPositionWithOnlyETH();

        TestVars memory vars;
        uint256 amount1Desired = 1 ether; // 1 ETH
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use position
        uint256 sharesToUse = vars.sharesMinted / 2; // Use half of the shares

        // Calculate the amount of tokens needed for the liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(sharesToUse)
        );

        // Give allowance from address(this) to positionManager for the calculated amounts
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(sharesToUse)
        });

        bytes memory useData = abi.encode(useParams, "");
        positionManager.usePosition(IHandler(address(handler)), useData);

        // Check if liquidity is used
        (, uint128 liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        assertEq(liquidityUsed, sharesToUse, "Liquidity used should match shares used");

        // Unuse position
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(sharesToUse)
        });

        bytes memory unuseData = abi.encode(unuseParams, "");
        positionManager.unusePosition(IHandler(address(handler)), unuseData);

        (, liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        (vars.balanceBefore.balance0, vars.balanceBefore.balance1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityUsed)
        );

        assertLt(vars.balanceBefore.balance0, 99999, "Dust amount of USDC should be less than 99999");
        assertLt(vars.balanceBefore.balance1, 100000000000, "Dust amount of ETH should be less than 99999");
    }

    function testUseAndUnusePositionInRange() public {
        // First, run the testMintPositionInRange test
        testMintPositionInRange();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use position
        uint256 sharesToUse = vars.sharesMinted / 2; // Use half of the shares

        // Calculate the amount of tokens needed for the liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(sharesToUse)
        );

        // Give allowance from address(this) to positionManager for the calculated amounts
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(sharesToUse)
        });

        bytes memory useData = abi.encode(useParams, "");
        positionManager.usePosition(IHandler(address(handler)), useData);

        // Check if liquidity is used
        (, uint128 liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        assertEq(liquidityUsed, sharesToUse, "Liquidity used should match shares used");

        // Unuse position
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(sharesToUse)
        });

        bytes memory unuseData = abi.encode(unuseParams, "");
        positionManager.unusePosition(IHandler(address(handler)), unuseData);

        (, liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        (vars.balanceBefore.balance0, vars.balanceBefore.balance1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityUsed)
        );

        assertLt(vars.balanceBefore.balance0, 99999, "Dust amount of USDC should be less than 99999");
        assertLt(vars.balanceBefore.balance1, 100000000000, "Dust amount of ETH should be less than 100000000000");
    }

    function testFuzzUseAndUnusePositionWithOnlyUSDC(uint256 usePercentage) public {
        // First, run the testMintPositionWithOnlyUSDC test
        testMintPositionWithOnlyUSDC();

        // Bound the usePercentage between 1% and 100%
        usePercentage = bound(usePercentage, 1, 100);

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use position
        uint256 sharesToUse = (vars.sharesMinted * usePercentage) / 100;

        // Calculate the amount of tokens needed for the liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(sharesToUse)
        );

        // Give allowance from owner to positionManager for the calculated amounts
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(sharesToUse)
        });

        bytes memory useData = abi.encode(useParams, "");
        positionManager.usePosition(IHandler(address(handler)), useData);

        // Check if liquidity is used
        (, uint128 liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        assertEq(liquidityUsed, sharesToUse, "Liquidity used should match shares used");

        // Unuse position
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(sharesToUse)
        });

        bytes memory unuseData = abi.encode(unuseParams, "");
        positionManager.unusePosition(IHandler(address(handler)), unuseData);

        (, liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        (vars.balanceBefore.balance0, vars.balanceBefore.balance1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityUsed)
        );

        assertLt(vars.balanceBefore.balance0, 99999, "Dust amount of USDC should be less than 99999");
        assertLt(vars.balanceBefore.balance1, 100000000000, "Dust amount of ETH should be less than 100000000000");
    }

    function testFuzzUseAndUnusePositionWithOnlyETH(uint256 usePercentage) public {
        // First, run the testMintPositionWithOnlyETH test
        testMintPositionWithOnlyETH();

        // Bound the usePercentage between 1% and 100%
        usePercentage = bound(usePercentage, 1, 100);

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use position
        uint256 sharesToUse = (vars.sharesMinted * usePercentage) / 100;

        // Calculate the amount of tokens needed for the liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(sharesToUse)
        );

        // Give allowance from owner to positionManager for the calculated amounts
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(sharesToUse)
        });

        bytes memory useData = abi.encode(useParams, "");
        positionManager.usePosition(IHandler(address(handler)), useData);

        // Check if liquidity is used
        (, uint128 liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        assertEq(liquidityUsed, sharesToUse, "Liquidity used should match shares used");

        // Unuse position
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(sharesToUse)
        });

        bytes memory unuseData = abi.encode(unuseParams, "");
        positionManager.unusePosition(IHandler(address(handler)), unuseData);

        (, liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        (vars.balanceBefore.balance0, vars.balanceBefore.balance1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityUsed)
        );

        assertLt(vars.balanceBefore.balance0, 100000000000, "Dust amount of USDC should be less than 100000000000");
        assertLt(vars.balanceBefore.balance1, 99999, "Dust amount of ETH should be less than 99999");
    }

    function testFuzzUseAndUnusePositionInRange(uint256 usePercentage) public {
        // First, run the testMintPositionInRange test
        testMintPositionInRange();

        // Bound the usePercentage between 1% and 100%
        usePercentage = bound(usePercentage, 1, 100);

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use position
        uint256 sharesToUse = (vars.sharesMinted * usePercentage) / 100;

        // Calculate the amount of tokens needed for the liquidity
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(sharesToUse)
        );

        // Give allowance from owner to positionManager for the calculated amounts
        USDC.approve(address(positionManager), amount0);
        ETH.approve(address(positionManager), amount1);

        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(sharesToUse)
        });

        bytes memory useData = abi.encode(useParams, "");
        positionManager.usePosition(IHandler(address(handler)), useData);

        // Check if liquidity is used
        (, uint128 liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        assertEq(liquidityUsed, sharesToUse, "Liquidity used should match shares used");

        // Unuse position
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(sharesToUse)
        });

        bytes memory unuseData = abi.encode(unuseParams, "");
        positionManager.unusePosition(IHandler(address(handler)), unuseData);

        (, liquidityUsed,,,,,,,,) = handler.tokenIds(vars.tokenId);

        (vars.balanceBefore.balance0, vars.balanceBefore.balance1) = LiquidityAmounts.getAmountsForLiquidity(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityUsed)
        );

        assertLt(vars.balanceBefore.balance0, 99999, "Dust amount of USDC should be less than 99999");
        assertLt(vars.balanceBefore.balance1, 100000000000, "Dust amount of ETH should be less than 100000000000");
    }

    function testReserveLiquidity() public {
        TestVars memory vars;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        uint256 amount1Desired = 0; // No ETH

        // First, run the testMintPositionWithOnlyUSDC test
        testMintPositionWithOnlyUSDC();

        // Now we can assume that a position has been minted
        // We need to retrieve the tokenId and sharesMinted from the previous test
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));
        vars.sharesMinted = handler.balanceOf(owner, vars.tokenId);

        // Use all the liquidity
        V3BaseHandler.UsePositionParams memory useParams = V3BaseHandler.UsePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(vars.sharesMinted)
        });

        positionManager.usePosition(IHandler(address(handler)), abi.encode(useParams, ""));

        // Attempt to burn (should fail due to no available liquidity)
        V3BaseHandler.BurnPositionParams memory burnParams = V3BaseHandler.BurnPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(vars.sharesMinted)
        });

        vm.prank(owner);
        vm.expectRevert(V3BaseHandler.InsufficientLiquidity.selector);
        positionManager.burnPosition(IHandler(address(handler)), abi.encode(burnParams, ""));

        // Reserve liquidity using wildcard function
        uint256 sharesToReserve = vars.sharesMinted / 2; // Reserve half of the shares
        V3BaseHandler.ReserveOperation memory reserveParams = V3BaseHandler.ReserveOperation({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesToReserve),
            isReserve: true
        });

        bytes memory reserveData =
            abi.encode(V3BaseHandler.WildcardActions.RESERVE_LIQUIDITY, abi.encode(reserveParams));
        vm.prank(owner);
        positionManager.wildcard(IHandler(address(handler)), reserveData);

        // Check that shares are burned after reserving
        uint256 remainingShares = handler.balanceOf(owner, vars.tokenId);
        assertEq(remainingShares, vars.sharesMinted - sharesToReserve, "Shares should be burned after reserving");

        reserveParams = V3BaseHandler.ReserveOperation({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(sharesToReserve),
            isReserve: false
        });

        // Attempt to withdraw reserved liquidity before cooldown period (should fail)
        bytes memory withdrawData =
            abi.encode(V3BaseHandler.WildcardActions.RESERVE_LIQUIDITY, abi.encode(reserveParams));
        vm.expectRevert(V3BaseHandler.BeforeReserveCooldown.selector);
        vm.prank(owner);
        positionManager.wildcard(IHandler(address(handler)), withdrawData);

        // Return some liquidity to the handler
        V3BaseHandler.UnusePositionParams memory unuseParams = V3BaseHandler.UnusePositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUnuse: uint128(vars.sharesMinted / 4) // Unuse 1/4 of the original shares
        });

        (, uint128 liquidityUsedBefore,,,,,,,,) = handler.tokenIds(vars.tokenId);

        USDC.approve(address(positionManager), 1000e6);
        ETH.approve(address(positionManager), 0);
        positionManager.unusePosition(IHandler(address(handler)), abi.encode(unuseParams, ""));

        (, uint128 liquidityUsedAfter,,,,,,,,) = handler.tokenIds(vars.tokenId);

        // Wait for cooldown period to pass
        vm.warp(block.timestamp + handler.reserveCooldownHook(address(0)));

        reserveParams = V3BaseHandler.ReserveOperation({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: uint128(liquidityUsedBefore - liquidityUsedAfter),
            isReserve: false
        });
        withdrawData = abi.encode(V3BaseHandler.WildcardActions.RESERVE_LIQUIDITY, abi.encode(reserveParams));

        vm.prank(owner);
        positionManager.wildcard(IHandler(address(handler)), withdrawData);
    }

    function testDonateTokens() public {
        // First, mint a position
        testMintPositionInRange();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing;

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        // Prepare donation amounts
        uint256 donateAmount0 = 1000e6; // 1000 USDC
        uint256 donateAmount1 = 0.5 ether; // 0.5 ETH

        // Mint tokens to donate
        USDC.mint(address(this), donateAmount0);
        ETH.mint(address(this), donateAmount1);

        // Approve tokens for PositionManager
        USDC.approve(address(positionManager), donateAmount0);
        ETH.approve(address(positionManager), donateAmount1);

        // Record initial feeReceiver balances
        uint256 initialFeeReceiver0 = USDC.balanceOf(feeReceiver);
        uint256 initialFeeReceiver1 = ETH.balanceOf(feeReceiver);

        // Prepare donation parameters
        V3BaseHandler.DonateParams memory donateParams = V3BaseHandler.DonateParams({
            pool: IV3Pool(address(pool)),
            hook: address(0),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            amount0: uint128(donateAmount0),
            amount1: uint128(donateAmount1)
        });

        // Donate tokens through PositionManager
        positionManager.donateToPosition(IHandler(address(handler)), abi.encode(donateParams, ""));

        // Check that the tokens were actually transferred from this contract
        assertEq(USDC.balanceOf(address(this)), 0, "This contract's USDC balance should be 0 after donation");
        assertEq(ETH.balanceOf(address(this)), 0, "This contract's ETH balance should be 0 after donation");

        // Check that the feeReceiver received the donated tokens
        assertEq(
            USDC.balanceOf(feeReceiver),
            initialFeeReceiver0 + donateAmount0,
            "FeeReceiver should have received donated USDC"
        );
        assertEq(
            ETH.balanceOf(feeReceiver),
            initialFeeReceiver1 + donateAmount1,
            "FeeReceiver should have received donated ETH"
        );
    }

    function testCollectFees() public {
        // Step 1: Reuse the donation test to mint a position and perform a donation
        testMintPositionInRange();

        // Retrieve the position details
        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) - 10 * tickSpacing;
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) + 10 * tickSpacing;
        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(0), vars.tickLower, vars.tickUpper));

        // Step 2: Perform a small swap to generate more fees
        uint256 swapAmount = 10000e6; // 1,000 USDC
        uint256 swapAmount1 = 5 ether; // 0.5 ETH
        vm.startPrank(address(this));
        USDC.mint(address(this), swapAmount);
        USDC.approve(address(pool), swapAmount);
        ETH.mint(address(this), swapAmount1);
        ETH.approve(address(pool), swapAmount1);

        pool.swap(
            address(this),
            true,
            int256(swapAmount),
            TickMath.MIN_SQRT_RATIO + 1, // Swap to the upper tick
            abi.encode(address(this))
        );

        pool.swap(
            address(this),
            false,
            int256(swapAmount1),
            TickMath.MAX_SQRT_RATIO - 1, // Swap to the upper tick
            abi.encode(address(this))
        );

        vm.stopPrank();

        (
            ,
            ,
            uint256 feeGrowthInside0LastX128Before,
            uint256 feeGrowthInside1LastX128Before,
            uint256 tokensOwed0Before,
            uint256 tokensOwed1Before,
            ,
            ,
            ,
        ) = handler.tokenIds(vars.tokenId);

        // Step 3: Call the wildcard function to collect fees
        bytes memory collectData = abi.encode(
            V3BaseHandler.WildcardActions.COLLECT_FEES,
            abi.encode(
                IV3Pool(address(pool)),
                address(0), // hook
                vars.tickLower,
                vars.tickUpper
            )
        );

        positionManager.wildcard(IHandler(address(handler)), collectData);

        (
            ,
            ,
            uint256 feeGrowthInside0LastX128After,
            uint256 feeGrowthInside1LastX128After,
            uint256 tokensOwed0After,
            uint256 tokensOwed1After,
            ,
            ,
            ,
        ) = handler.tokenIds(vars.tokenId);

        assertTrue(USDC.balanceOf(feeReceiver) > 0, "Should have collected USDC fees");
        assertTrue(ETH.balanceOf(feeReceiver) > 0, "Should have collected ETH fees");

        assertTrue(
            feeGrowthInside0LastX128After >= feeGrowthInside0LastX128Before,
            "FeeGrowthInside0LastX128 should not decrease"
        );
        assertTrue(
            feeGrowthInside1LastX128After >= feeGrowthInside1LastX128Before,
            "FeeGrowthInside1LastX128 should not decrease"
        );
        assertEq(tokensOwed0After, 0, "TokensOwed0 should be 0 after collection");
        assertEq(tokensOwed1After, 0, "TokensOwed1 should be 0 after collection");
    }

    // Add this function to handle the swap callback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) {
            USDC.transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ETH.transfer(msg.sender, uint256(amount1Delta));
        }
    }
}
