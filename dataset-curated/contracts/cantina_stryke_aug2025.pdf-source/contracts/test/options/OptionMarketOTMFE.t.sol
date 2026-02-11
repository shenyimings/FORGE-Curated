// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {UniswapV3Handler} from "../../src/handlers/uniswap-v3/UniswapV3Handler.sol";
import {PositionManager} from "../../src/PositionManager.sol";
import {OptionMarketOTMFE} from "../../src/apps/options/OptionMarketOTMFE.sol";
import {OptionPricingLinearV2} from "../../src/apps/options/pricing/OptionPricingLinearV2.sol";
import {ClammFeeStrategyV2} from "../../src/apps/options/pricing/fees/ClammFeeStrategyV2.sol";
import {UniswapV3FactoryDeployer} from "../../test/handlers/uniswap-v3/uniswap-v3-utils/UniswapV3FactoryDeployer.sol";

import {UniswapV3PoolUtils} from "../../test/handlers/uniswap-v3/uniswap-v3-utils/UniswapV3PoolUtils.sol";
import {UniswapV3LiquidityManagement} from
    "../../test/handlers/uniswap-v3/uniswap-v3-utils/UniswapV3LiquidityManagement.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IVerifiedSpotPrice} from "../../src/interfaces/IVerifiedSpotPrice.sol";
import {IOptionMarketOTMFE} from "../../src/interfaces/apps/options/IOptionMarketOTMFE.sol";
import {PoolSpotPrice} from "../../src/apps/options/pricing/PoolSpotPrice.sol";

import {ISwapper} from "../../src/interfaces/ISwapper.sol";

import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {MockHook} from "../../test/mocks/MockHook.sol";
import {IV3Pool} from "../../src/interfaces/handlers/V3/IV3Pool.sol";
import {V3BaseHandler} from "../../src/handlers/V3BaseHandler.sol";
import {IHandler} from "../../src/interfaces/IHandler.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {Tick} from "@uniswap/v3-core/contracts/libraries/Tick.sol";

import {OpenSettlement} from "../../src/periphery/OpenSettlement.sol";
import {AddLiquidityRouter} from "../../src/periphery/routers/AddLiquidityRouter.sol";

import {MintOptionFirewall} from "../../src/periphery/firewalls/MintOptionFirewall.sol";
import {ExerciseOptionFirewall} from "../../src/periphery/firewalls/ExerciseOptionFirewall.sol";

contract OptionMarketOTMFETest is Test, UniswapV3FactoryDeployer {
    using TickMath for int24;

    PositionManager public positionManager;
    UniswapV3Handler public handler;

    OptionMarketOTMFE public optionMarketOTMFE;
    OptionPricingLinearV2 public optionPricingLinearV2;
    ClammFeeStrategyV2 public clammFeeStrategyV2;

    UniswapV3FactoryDeployer public factoryDeployer;
    IUniswapV3Factory public factory;

    UniswapV3PoolUtils public uniswapV3PoolUtils;
    UniswapV3LiquidityManagement public uniswapV3LiquidityManagement;

    OpenSettlement public openSettlement;
    AddLiquidityRouter public addLiquidityRouter;
    MintOptionFirewall public mintOptionFirewall;
    ExerciseOptionFirewall public exerciseOptionFirewall;

    MockERC20 public USDC; // token0
    MockERC20 public ETH; // token1

    MockERC20 public token0;
    MockERC20 public token1;

    address public feeReceiver = makeAddr("feeReceiver");

    address public publicFeeRecipient = makeAddr("publicFeeRecipient");

    address public owner = makeAddr("owner");

    address public user = makeAddr("user");

    address public trader = makeAddr("trader");

    address public settler = makeAddr("settler");

    address public garbage = makeAddr("garbage");

    uint256 verifiedSignerPrivateKey = uint256(keccak256("verifiedSigner"));
    address verifiedSigner = vm.addr(verifiedSignerPrivateKey);

    IUniswapV3Pool public pool;

    MockHook public mockHook;

    PoolSpotPrice public poolSpotPrice;

    function setUp() public {
        // Deploy the Uniswap V3 Factory
        factory = IUniswapV3Factory(deployUniswapV3Factory());

        // Deploy mock tokens for testing
        USDC = new MockERC20("USD Coin", "USDC", 6);
        ETH = new MockERC20("Ethereum", "ETH", 18);

        uniswapV3PoolUtils = new UniswapV3PoolUtils();

        uniswapV3LiquidityManagement = new UniswapV3LiquidityManagement(address(factory));

        uint160 sqrtPriceX96 = 1771595571142957166518320255467520;
        pool = IUniswapV3Pool(uniswapV3PoolUtils.deployAndInitializePool(factory, ETH, USDC, 500, sqrtPriceX96));

        uniswapV3PoolUtils.addLiquidity(
            UniswapV3PoolUtils.AddLiquidityStruct({
                liquidityManager: address(uniswapV3LiquidityManagement),
                pool: pool,
                user: owner,
                desiredAmount0: 10_000_000e6,
                desiredAmount1: 10 ether,
                desiredTickLower: 200010,
                desiredTickUpper: 201010,
                requireMint: true
            })
        );

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

        handler.updateHandlerSettings(address(positionManager), true, address(0), 6 hours, address(feeReceiver));

        mockHook = new MockHook();

        handler.registerHook(
            address(mockHook),
            IHandler.HookPermInfo({
                onMint: false,
                onBurn: false,
                onUse: false,
                onUnuse: false,
                onDonate: false,
                allowSplit: false
            })
        );

        optionPricingLinearV2 = new OptionPricingLinearV2();

        clammFeeStrategyV2 = new ClammFeeStrategyV2();

        poolSpotPrice = new PoolSpotPrice();

        mintOptionFirewall = new MintOptionFirewall(verifiedSigner);
        exerciseOptionFirewall = new ExerciseOptionFirewall(verifiedSigner);

        optionMarketOTMFE = new OptionMarketOTMFE(
            address(positionManager),
            address(optionPricingLinearV2),
            address(clammFeeStrategyV2),
            address(ETH),
            address(USDC),
            address(pool),
            address(poolSpotPrice)
        );

        exerciseOptionFirewall.updateWhitelistedMarket(address(optionMarketOTMFE), true);

        optionPricingLinearV2.updateVolatilityOffset(address(optionMarketOTMFE), 10_000);
        optionPricingLinearV2.updateVolatilityMultiplier(address(optionMarketOTMFE), 1_000);
        optionPricingLinearV2.updateMinOptionPricePercentage(address(optionMarketOTMFE), 10_000_000);

        uint256[] memory ttls = new uint256[](1);
        uint256[] memory ttlIV = new uint256[](1);

        ttls[0] = 86400;
        ttlIV[0] = 50;

        optionPricingLinearV2.updateIVs(address(optionMarketOTMFE), ttls, ttlIV);

        vm.warp(1729238400);

        clammFeeStrategyV2.registerOptionMarket(address(optionMarketOTMFE), 350000);

        openSettlement = new OpenSettlement(settler, publicFeeRecipient, 1000, 500);

        optionMarketOTMFE.updatePoolApporvals(
            address(exerciseOptionFirewall), true, address(pool), true, 86400, 1729065600, true, 10 minutes
        );
        optionMarketOTMFE.updatePoolApporvals(
            address(openSettlement), true, address(pool), true, 86400, 1729065600, true, 10 minutes
        );

        optionMarketOTMFE.updatePoolSettings(
            address(feeReceiver),
            address(0),
            address(clammFeeStrategyV2),
            address(optionPricingLinearV2),
            address(poolSpotPrice),
            100,
            887272,
            -887272,
            0
        );

        optionMarketOTMFE.setApprovedSwapperAndHook(address(this), true, address(mockHook), true);

        optionMarketOTMFE.setApprovedMinter(address(mintOptionFirewall), true);

        positionManager.updateWhitelistHandlerWithApp(address(handler), address(optionMarketOTMFE), true);

        addLiquidityRouter = new AddLiquidityRouter(address(positionManager));

        vm.stopPrank();

        // Initialize the pool with sqrtPriceX96 representing 1 ETH = 2000 USDC
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

    struct PerpPositionDataVars {
        uint128 perpTickArrayLen;
        int24 positionTickLower;
        int24 positionTickUpper;
        bool isLong;
        uint128 remainingFees;
        uint64 lastFeeAccrued;
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

    function addLiquidityForCALL() public returns (uint256) {
        TestVars memory vars;
        uint256 amount1Desired = 1 ether; // 1 ETH
        uint256 amount0Desired = 0; // No USDC

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        console.log("currentTick", vars.currentTick);

        // Calculate tick range
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing; // 1 tick spaces wide

        vm.startPrank(user);
        ETH.mint(user, amount1Desired);
        ETH.approve(address(addLiquidityRouter), amount1Desired);
        vars.balanceBefore.balance1 = ETH.balanceOf(user);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(mockHook),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = addLiquidityRouter.addLiquidity(
            IHandler(address(handler)),
            abi.encode(params, ""),
            AddLiquidityRouter.RangeCheckData({
                minTickLower: vars.currentTick - 10,
                maxTickUpper: vars.currentTick + 10,
                minSqrtPriceX96: vars.sqrtPriceX96 - 10,
                maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
                deadline: block.timestamp + 1 hours
            })
        );

        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(mockHook), vars.tickLower, vars.tickUpper));

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

        assertEq(handler.balanceOf(user, vars.tokenId), vars.sharesMinted, "user's balance should equal shares minted");

        vars.balanceAfter.balance1 = ETH.balanceOf(user);
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

        return vars.sharesMinted;
    }

    function addLiquidityForPUT() public returns (uint256) {
        TestVars memory vars;
        uint256 amount0Desired = 1000e6; // 1000 USDC
        uint256 amount1Desired = 0; // No ETH

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing; // 1 tick spaces wide

        vm.startPrank(user);
        USDC.mint(user, amount0Desired);
        USDC.approve(address(addLiquidityRouter), amount0Desired);
        vars.balanceBefore.balance0 = USDC.balanceOf(user);

        vars.liquidity = LiquidityAmounts.getLiquidityForAmounts(
            vars.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            amount0Desired,
            amount1Desired
        );

        V3BaseHandler.MintPositionParams memory params = V3BaseHandler.MintPositionParams({
            pool: IV3Pool(address(pool)),
            hook: address(mockHook),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidity: vars.liquidity
        });

        vars.sharesMinted = addLiquidityRouter.addLiquidity(
            IHandler(address(handler)),
            abi.encode(params, ""),
            AddLiquidityRouter.RangeCheckData({
                minTickLower: vars.currentTick - 10,
                maxTickUpper: vars.currentTick + 10,
                minSqrtPriceX96: vars.sqrtPriceX96 - 10,
                maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
                deadline: block.timestamp + 1 hours
            })
        );
        assertTrue(vars.sharesMinted > 0, "Shares minted should be greater than 0");

        vars.tokenId =
            handler.getHandlerIdentifier(abi.encode(address(pool), address(mockHook), vars.tickLower, vars.tickUpper));

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

        assertEq(handler.balanceOf(user, vars.tokenId), vars.sharesMinted, "user's balance should equal shares minted");

        vars.balanceAfter.balance0 = USDC.balanceOf(user);
        assertTrue(vars.balanceAfter.balance0 < vars.balanceBefore.balance0, "USDC balance should have decreased");
        assertTrue(
            vars.balanceBefore.balance0 - vars.balanceAfter.balance0 <= amount0Desired,
            "USDC spent should not exceed desired amount"
        );

        (uint128 poolLiquidity,,,,) =
            pool.positions(keccak256(abi.encodePacked(address(handler), vars.tickLower, vars.tickUpper)));
        assertEq(poolLiquidity, info.totalLiquidity, "Pool liquidity should match total liquidity in handler");

        vm.stopPrank();

        return vars.sharesMinted;
    }

    function testBuyCallOption_InBufferTime() public {
        TestVars memory vars;

        // Setup
        vars.sharesMinted = addLiquidityForCALL();

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range for the long position
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Prepare option parameters
        OptionMarketOTMFE.OptionTicks[] memory optionTicks = new OptionMarketOTMFE.OptionTicks[](1);
        optionTicks[0] = OptionMarketOTMFE.OptionTicks({
            _handler: IHandler(address(handler)),
            pool: pool,
            hook: address(mockHook),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(vars.sharesMinted)
        });

        OptionMarketOTMFE.OptionParams memory params = OptionMarketOTMFE.OptionParams({
            optionTicks: optionTicks,
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            ttl: 86400, // 1 day
            isCall: true,
            maxCostAllowance: 1e18 // 1 ETH max cost
        });

        // Get current price and calculate expected premium
        uint256 currentPrice = poolSpotPrice.getSpotPrice(pool, address(ETH), ETH.decimals());
        uint256 strike = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, params.tickUpper);
        uint256 expectedPremium = optionMarketOTMFE.getPremiumAmount(
            address(mockHook),
            false, // isCall
            block.timestamp + params.ttl,
            params.ttl,
            strike,
            currentPrice,
            vars.sharesMinted
        );

        // Approve USDC spending for premium payment
        vm.startPrank(trader);
        USDC.mint(trader, expectedPremium);
        USDC.approve(address(optionMarketOTMFE), expectedPremium);

        // Record balances before minting
        uint256 traderUSDCBefore = USDC.balanceOf(trader);
        uint256 marketUSDCBefore = USDC.balanceOf(address(optionMarketOTMFE));

        // Mint the option
        vm.expectRevert(OptionMarketOTMFE.InBUFFER_TIME.selector);
        optionMarketOTMFE.mintOption(params);

        vm.stopPrank();
    }

    function testBuyCallOption() public {
        vm.warp(block.timestamp + 10 minutes);
        TestVars memory vars;

        // Setup
        vars.sharesMinted = addLiquidityForCALL();

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range for the long position
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Prepare option parameters
        IOptionMarketOTMFE.OptionTicks[] memory optionTicks = new IOptionMarketOTMFE.OptionTicks[](1);
        optionTicks[0] = IOptionMarketOTMFE.OptionTicks({
            _handler: IHandler(address(handler)),
            pool: pool,
            hook: address(mockHook),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(vars.sharesMinted)
        });

        IOptionMarketOTMFE.OptionParams memory params = IOptionMarketOTMFE.OptionParams({
            optionTicks: optionTicks,
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            ttl: 86400, // 1 day
            isCall: true,
            maxCostAllowance: 0 // 1 ETH max cost
        });

        // Get current price and calculate expected premium
        uint256 currentPrice = poolSpotPrice.getSpotPrice(pool, address(ETH), ETH.decimals());
        uint256 strike = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, params.tickUpper);
        uint256 amount = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(vars.sharesMinted)
        );

        uint256 expectedPremium = optionMarketOTMFE.getPremiumAmount(
            address(mockHook),
            false, // isCall
            block.timestamp + params.ttl - 10 minutes,
            params.ttl,
            strike,
            currentPrice,
            amount
        );

        uint256 expectedFees = optionMarketOTMFE.getFee(amount, expectedPremium);

        params.maxCostAllowance = expectedPremium + expectedFees;

        // Approve ETH spending for premium payment
        vm.startPrank(trader);
        ETH.mint(trader, expectedPremium + expectedFees);
        ETH.approve(address(mintOptionFirewall), expectedPremium + expectedFees);

        MintOptionFirewall.Signature[] memory signature = new MintOptionFirewall.Signature[](1);

        (signature[0].v, signature[0].r, signature[0].s) = _createSignature(
            trader,
            handler.getHandlerIdentifier(abi.encode(address(pool), address(mockHook), vars.tickLower, vars.tickUpper)),
            MintOptionFirewall.RangeCheckData({
                user: trader,
                pool: address(pool),
                market: address(optionMarketOTMFE),
                minTickLower: vars.currentTick - 10,
                maxTickUpper: vars.currentTick + 10,
                minSqrtPriceX96: vars.sqrtPriceX96 - 10,
                maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
                deadline: block.timestamp + 1 hours
            })
        );

        // Record balances before minting
        uint256 traderETHBefore = ETH.balanceOf(trader);
        uint256 marketETHBefore = ETH.balanceOf(address(optionMarketOTMFE));

        MintOptionFirewall.RangeCheckData[] memory rangeCheckData = new MintOptionFirewall.RangeCheckData[](1);
        rangeCheckData[0] = MintOptionFirewall.RangeCheckData({
            user: trader,
            pool: address(pool),
            market: address(optionMarketOTMFE),
            minTickLower: vars.currentTick - 10,
            maxTickUpper: vars.currentTick + 10,
            minSqrtPriceX96: vars.sqrtPriceX96 - 10,
            maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
            deadline: block.timestamp + 1 hours
        });

        // Mint the option
        mintOptionFirewall.mintOption(
            MintOptionFirewall.OptionData({
                market: IOptionMarketOTMFE(address(optionMarketOTMFE)),
                optionParams: params,
                optionRecipient: trader,
                self: false
            }),
            rangeCheckData,
            signature
        );

        // Record balances after minting
        uint256 traderETHAfter = ETH.balanceOf(trader);

        // Assertions
        assertEq(optionMarketOTMFE.balanceOf(trader), 1, "Trader should own 1 option NFT");
        assertEq(
            traderETHBefore - traderETHAfter, expectedPremium + expectedFees, "Trader should pay the correct premium"
        );

        // Check option data
        OptionMarketOTMFE.OptionData memory optionData;

        (optionData.opTickArrayLen, optionData.expiry, optionData.tickLower, optionData.tickUpper, optionData.isCall) =
            optionMarketOTMFE.opData(1);

        assertEq(optionData.opTickArrayLen, 1, "Option should have 1 tick");
        assertEq(optionData.tickLower, vars.tickLower, "Lower tick should match");
        assertEq(optionData.tickUpper, vars.tickUpper, "Upper tick should match");
        assertTrue(optionData.isCall, "Option should be a call");
        assertEq(optionData.expiry, block.timestamp + params.ttl - 10 minutes, "Expiry should be correct");

        vm.stopPrank();
    }

    function testBuyPutOption() public {
        vm.warp(block.timestamp + 10 minutes);
        TestVars memory vars;

        // Setup
        vars.sharesMinted = addLiquidityForPUT();

        // Get current price and tick
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Calculate tick range for the long position
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        // Prepare option parameters
        IOptionMarketOTMFE.OptionTicks[] memory optionTicks = new IOptionMarketOTMFE.OptionTicks[](1);
        optionTicks[0] = IOptionMarketOTMFE.OptionTicks({
            _handler: IHandler(address(handler)),
            pool: pool,
            hook: address(mockHook),
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            liquidityToUse: uint128(vars.sharesMinted)
        });

        IOptionMarketOTMFE.OptionParams memory params = IOptionMarketOTMFE.OptionParams({
            optionTicks: optionTicks,
            tickLower: vars.tickLower,
            tickUpper: vars.tickUpper,
            ttl: 86400, // 1 day
            isCall: false,
            maxCostAllowance: 0 // Will be set later
        });

        // Get current price and calculate expected premium
        uint256 currentPrice = poolSpotPrice.getSpotPrice(pool, address(ETH), ETH.decimals());
        uint256 strike = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, params.tickLower);
        uint256 amount = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(vars.sharesMinted)
        );

        uint256 expectedPremium = optionMarketOTMFE.getPremiumAmount(
            address(mockHook),
            true, // isPut
            block.timestamp + params.ttl - 10 minutes,
            params.ttl,
            strike,
            currentPrice,
            (amount * (10 ** USDC.decimals())) / strike
        );

        uint256 expectedFees = optionMarketOTMFE.getFee(amount, expectedPremium);

        params.maxCostAllowance = expectedPremium + expectedFees;

        // Approve USDC spending for premium payment
        vm.startPrank(trader);
        USDC.mint(trader, expectedPremium + expectedFees);
        USDC.approve(address(mintOptionFirewall), expectedPremium + expectedFees);

        MintOptionFirewall.Signature[] memory signature = new MintOptionFirewall.Signature[](1);

        (signature[0].v, signature[0].r, signature[0].s) = _createSignature(
            trader,
            handler.getHandlerIdentifier(abi.encode(address(pool), address(mockHook), vars.tickLower, vars.tickUpper)),
            MintOptionFirewall.RangeCheckData({
                user: trader,
                pool: address(pool),
                market: address(optionMarketOTMFE),
                minTickLower: vars.currentTick - 10,
                maxTickUpper: vars.currentTick + 10,
                minSqrtPriceX96: vars.sqrtPriceX96 - 10,
                maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
                deadline: block.timestamp + 1 hours
            })
        );
        // Record balances before minting
        uint256 traderUSDCBefore = USDC.balanceOf(trader);
        uint256 marketUSDCBefore = USDC.balanceOf(address(optionMarketOTMFE));

        MintOptionFirewall.RangeCheckData[] memory rangeCheckData = new MintOptionFirewall.RangeCheckData[](1);
        rangeCheckData[0] = MintOptionFirewall.RangeCheckData({
            user: trader,
            pool: address(pool),
            market: address(optionMarketOTMFE),
            minTickLower: vars.currentTick - 10,
            maxTickUpper: vars.currentTick + 10,
            minSqrtPriceX96: vars.sqrtPriceX96 - 10,
            maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
            deadline: block.timestamp + 1 hours
        });

        // Mint the option
        mintOptionFirewall.mintOption(
            MintOptionFirewall.OptionData({
                market: IOptionMarketOTMFE(address(optionMarketOTMFE)),
                optionParams: params,
                optionRecipient: trader,
                self: false
            }),
            rangeCheckData,
            signature
        );

        // Record balances after minting
        uint256 traderUSDCAfter = USDC.balanceOf(trader);

        // Assertions
        assertEq(optionMarketOTMFE.balanceOf(trader), 1, "Trader should own 1 option NFT");
        assertEq(
            traderUSDCBefore - traderUSDCAfter, expectedPremium + expectedFees, "Trader should pay the correct premium"
        );

        // Check option data
        OptionMarketOTMFE.OptionData memory optionData;

        (optionData.opTickArrayLen, optionData.expiry, optionData.tickLower, optionData.tickUpper, optionData.isCall) =
            optionMarketOTMFE.opData(1);
        assertEq(optionData.opTickArrayLen, 1, "Option should have 1 tick");
        assertEq(optionData.tickLower, vars.tickLower, "Lower tick should match");
        assertEq(optionData.tickUpper, vars.tickUpper, "Upper tick should match");
        assertFalse(optionData.isCall, "Option should be a put");
        assertEq(optionData.expiry, block.timestamp + params.ttl - 10 minutes, "Expiry should be correct");

        vm.stopPrank();
    }

    function testExerciseCallOption() public {
        // Setup: Buy a call option
        testBuyCallOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 85200); // 10 minutes before

        // price increase
        uint256 swapAmount = 10000e6; // 50,000 USDC
        vm.startPrank(address(this));
        USDC.mint(address(this), swapAmount);
        USDC.approve(address(pool), swapAmount);

        pool.swap(
            address(0xD3AD),
            true,
            int256(swapAmount),
            TickMath.MIN_SQRT_RATIO + 1, // Swap to the upper tick
            abi.encode(address(this))
        );

        vm.stopPrank();
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        ExerciseOptionFirewall.RangeCheckData[] memory rangeCheckData = new ExerciseOptionFirewall.RangeCheckData[](1);
        rangeCheckData[0] = ExerciseOptionFirewall.RangeCheckData({
            user: trader,
            pool: address(pool),
            market: address(optionMarketOTMFE),
            minTickLower: vars.currentTick - 10,
            maxTickUpper: vars.currentTick + 10,
            minSqrtPriceX96: vars.sqrtPriceX96 - 10,
            maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
            deadline: block.timestamp + 1 hours
        });

        ExerciseOptionFirewall.Signature[] memory signature = new ExerciseOptionFirewall.Signature[](1);
        (signature[0].v, signature[0].r, signature[0].s) = _createSignatureExercise(
            trader,
            handler.getHandlerIdentifier(abi.encode(address(pool), address(mockHook), vars.tickLower, vars.tickUpper)),
            ExerciseOptionFirewall.RangeCheckData({
                user: trader,
                pool: address(pool),
                market: address(optionMarketOTMFE),
                minTickLower: vars.currentTick - 10,
                maxTickUpper: vars.currentTick + 10,
                minSqrtPriceX96: vars.sqrtPriceX96 - 10,
                maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
                deadline: block.timestamp + 1 hours
            })
        );

        // Exercise the option
        vm.startPrank(trader);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result = exerciseOptionFirewall.exerciseOption(
            IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams, rangeCheckData, signature
        );

        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 ethAmount = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(ETH), "Asset to use should be ETH");
        assertEq(address(result.assetToGet), address(USDC), "Asset to get should be USDC");
        assertTrue(result.totalProfit > 0, "Should have made a profit");
        assertEq(result.totalAssetRelocked, ethAmount, "Assets relocked");
        assertFalse(result.isSettle, "Should not be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickUpper);

        uint256 expectedProfit = vars.balanceAfter.balance0 - vars.balanceBefore.balance0;
        assertEq(result.totalProfit, expectedProfit, "Profit should be close to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testExercisePutOption() public {
        // Setup: Buy a put option
        testBuyPutOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 85200); // 10 minutes before expiry

        // Price decrease
        uint256 swapAmount = 5 ether; // 5 ETH
        vm.startPrank(address(this));
        ETH.mint(address(this), swapAmount);
        ETH.approve(address(pool), swapAmount);

        pool.swap(
            address(0xD3AD),
            false,
            int256(swapAmount),
            TickMath.MAX_SQRT_RATIO - 1, // Swap to the lower tick
            abi.encode(address(this))
        );

        vm.stopPrank();
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        ExerciseOptionFirewall.RangeCheckData[] memory rangeCheckData = new ExerciseOptionFirewall.RangeCheckData[](1);
        rangeCheckData[0] = ExerciseOptionFirewall.RangeCheckData({
            user: trader,
            pool: address(pool),
            market: address(optionMarketOTMFE),
            minTickLower: vars.currentTick - 10,
            maxTickUpper: vars.currentTick + 10,
            minSqrtPriceX96: vars.sqrtPriceX96 - 10,
            maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
            deadline: block.timestamp + 1 hours
        });

        ExerciseOptionFirewall.Signature[] memory signature = new ExerciseOptionFirewall.Signature[](1);
        (signature[0].v, signature[0].r, signature[0].s) = _createSignatureExercise(
            trader,
            handler.getHandlerIdentifier(abi.encode(address(pool), address(mockHook), vars.tickLower, vars.tickUpper)),
            ExerciseOptionFirewall.RangeCheckData({
                user: trader,
                pool: address(pool),
                market: address(optionMarketOTMFE),
                minTickLower: vars.currentTick - 10,
                maxTickUpper: vars.currentTick + 10,
                minSqrtPriceX96: vars.sqrtPriceX96 - 10,
                maxSqrtPriceX96: vars.sqrtPriceX96 + 10,
                deadline: block.timestamp + 1 hours
            })
        );

        // Exercise the option
        vm.startPrank(trader);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result = exerciseOptionFirewall.exerciseOption(
            IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams, rangeCheckData, signature
        );
        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 usdcAmount = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(USDC), "Asset to use should be USDC");
        assertEq(address(result.assetToGet), address(ETH), "Asset to get should be ETH");
        assertTrue(result.totalProfit > 0, "Should have made a profit");
        assertEq(result.totalAssetRelocked, usdcAmount, "Assets relocked");
        assertFalse(result.isSettle, "Should not be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickLower);

        uint256 expectedProfit = vars.balanceAfter.balance1 - vars.balanceBefore.balance1;
        assertEq(result.totalProfit, expectedProfit, "Profit should be equal to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testSettleCallOptionITM() public {
        // Setup: Buy a call option
        testBuyCallOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 86500); // 10 minutes before

        // price increase
        uint256 swapAmount = 10000e6; // 50,000 USDC
        vm.startPrank(address(this));
        USDC.mint(address(this), swapAmount);
        USDC.approve(address(pool), swapAmount);

        pool.swap(
            address(0xD3AD),
            true,
            int256(swapAmount),
            TickMath.MIN_SQRT_RATIO + 1, // Swap to the upper tick
            abi.encode(address(this))
        );

        vm.stopPrank();

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        // Exercise the option
        vm.startPrank(verifiedSigner);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result =
            exerciseOptionFirewall.settleOption(IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams);

        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 ethAmount = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(ETH), "Asset to use should be ETH");
        assertEq(address(result.assetToGet), address(USDC), "Asset to get should be USDC");
        assertTrue(result.totalProfit > 0, "Should have made a profit");
        assertEq(result.totalAssetRelocked, ethAmount, "Assets relocked");
        assertTrue(result.isSettle, "Should be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickUpper);

        uint256 expectedProfit = vars.balanceAfter.balance0 - vars.balanceBefore.balance0;
        assertEq(result.totalProfit, expectedProfit, "Profit should be close to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testSettleCallOptionITMOpenSettlement() public {
        // Setup: Buy a call option
        testBuyCallOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 86500); // 10 minutes before

        // price increase
        uint256 swapAmount = 10000e6; // 50,000 USDC
        vm.startPrank(address(this));
        USDC.mint(address(this), swapAmount);
        USDC.approve(address(pool), swapAmount);

        pool.swap(
            address(0xD3AD),
            true,
            int256(swapAmount),
            TickMath.MIN_SQRT_RATIO + 1, // Swap to the upper tick
            abi.encode(address(this))
        );

        vm.stopPrank();

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        // Exercise the option
        vm.startPrank(garbage);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result =
            openSettlement.openSettle(IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams);
        console.log("result.totalProfit", result.totalProfit);
        console.log("Public Fee Recipient Balance", USDC.balanceOf(openSettlement.publicFeeRecipient()));
        console.log("Settler Balance", USDC.balanceOf(garbage));
        console.log("Trader Balance", USDC.balanceOf(trader));
    }

    function testSettlePutOptionITM() public {
        // Setup: Buy a put option
        testBuyPutOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 86500); // 10 minutes before expiry

        // Price decrease
        uint256 swapAmount = 5 ether; // 5 ETH
        vm.startPrank(address(this));
        ETH.mint(address(this), swapAmount);
        ETH.approve(address(pool), swapAmount);

        pool.swap(
            address(0xD3AD),
            false,
            int256(swapAmount),
            TickMath.MAX_SQRT_RATIO - 1, // Swap to the lower tick
            abi.encode(address(this))
        );

        vm.stopPrank();

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        // Exercise the option
        vm.startPrank(verifiedSigner);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result =
            exerciseOptionFirewall.settleOption(IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams);

        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 usdcAmount = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(USDC), "Asset to use should be USDC");
        assertEq(address(result.assetToGet), address(ETH), "Asset to get should be ETH");
        assertTrue(result.totalProfit > 0, "Should have made a profit");
        assertEq(result.totalAssetRelocked, usdcAmount, "Assets relocked");
        assertTrue(result.isSettle, "Should be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickLower);

        uint256 expectedProfit = vars.balanceAfter.balance1 - vars.balanceBefore.balance1;
        assertEq(result.totalProfit, expectedProfit, "Profit should be equal to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testSettleCallOptionOTM() public {
        // Setup: Buy a call option
        testBuyCallOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 86500); // 10 minutes before

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        // Exercise the option
        vm.startPrank(verifiedSigner);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result =
            exerciseOptionFirewall.settleOption(IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams);

        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 ethAmount = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(ETH), "Asset to use should be ETH");
        assertEq(address(result.assetToGet), address(USDC), "Asset to get should be USDC");
        assertEq(result.totalProfit, 0, "Should not have made a profit");
        assertEq(result.totalAssetRelocked, ethAmount, "Assets relocked");
        assertTrue(result.isSettle, "Should be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickUpper);

        uint256 expectedProfit = vars.balanceAfter.balance0 - vars.balanceBefore.balance0;

        assertEq(result.totalProfit, expectedProfit, "Profit should be close to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testSettleCallOptionOTMOpenSettlement() public {
        // Setup: Buy a call option
        testBuyCallOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 86500); // 10 minutes before

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        // Exercise the option
        vm.startPrank(settler);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result =
            openSettlement.openSettle(IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams);

        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 ethAmount = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(ETH), "Asset to use should be ETH");
        assertEq(address(result.assetToGet), address(USDC), "Asset to get should be USDC");
        assertEq(result.totalProfit, 0, "Should not have made a profit");
        assertEq(result.totalAssetRelocked, ethAmount, "Assets relocked");
        assertTrue(result.isSettle, "Should be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickUpper);

        uint256 expectedProfit = vars.balanceAfter.balance0 - vars.balanceBefore.balance0;

        assertEq(result.totalProfit, expectedProfit, "Profit should be close to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testSettlePutOptionOTM() public {
        // Setup: Buy a put option
        testBuyPutOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickLower = ((vars.currentTick / tickSpacing) * tickSpacing) + tickSpacing;
        vars.tickUpper = vars.tickLower + 1 * tickSpacing;

        // Warp time to just before expiry
        vm.warp(block.timestamp + 86500); // 10 minutes before expiry

        // Prepare for exercise
        uint256 optionId = 1; // Assuming this is the first option minted
        uint256[] memory liquidityToSettle = new uint256[](1);
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(optionId, 0);
        liquidityToSettle[0] = liquidityToUse;

        ISwapper[] memory swappers = new ISwapper[](1);
        swappers[0] = ISwapper(address(this));

        bytes[] memory swapData = new bytes[](1);
        swapData[0] = ""; // No swap data needed

        IOptionMarketOTMFE.SettleOptionParams memory settleParams = IOptionMarketOTMFE.SettleOptionParams({
            optionId: optionId,
            swapper: swappers,
            swapData: swapData,
            liquidityToSettle: liquidityToSettle
        });

        // Exercise the option
        vm.startPrank(verifiedSigner);
        vars.balanceBefore.balance0 = USDC.balanceOf(trader);
        vars.balanceBefore.balance1 = ETH.balanceOf(trader);

        IOptionMarketOTMFE.AssetsCache memory result =
            exerciseOptionFirewall.settleOption(IOptionMarketOTMFE(address(optionMarketOTMFE)), optionId, settleParams);

        vars.balanceAfter.balance0 = USDC.balanceOf(trader);
        vars.balanceAfter.balance1 = ETH.balanceOf(trader);
        vm.stopPrank();

        // Assertions
        uint256 usdcAmount = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(vars.tickLower),
            TickMath.getSqrtRatioAtTick(vars.tickUpper),
            uint128(liquidityToUse)
        );
        assertEq(address(result.assetToUse), address(USDC), "Asset to use should be USDC");
        assertEq(address(result.assetToGet), address(ETH), "Asset to get should be ETH");
        assertEq(result.totalProfit, 0, "Should not have made a profit");
        assertEq(result.totalAssetRelocked, usdcAmount, "Assets relocked");
        assertTrue(result.isSettle, "Should be a settlement");

        // Calculate expected profit
        uint256 strikePrice = optionMarketOTMFE.getPricePerCallAssetViaTick(pool, vars.tickLower);

        uint256 expectedProfit = vars.balanceAfter.balance1 - vars.balanceBefore.balance1;
        assertEq(result.totalProfit, expectedProfit, "Profit should be equal to expected");
        assertApproxEqRel(result.totalProfit, expectedProfit, 1e16, "Profit should be close to expected");
    }

    function testSplitOption() public {
        // Setup: Buy a call option
        testBuyCallOption();

        TestVars memory vars;
        (vars.sqrtPriceX96, vars.currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        vars.tickUpper = ((vars.currentTick / tickSpacing) * tickSpacing) - tickSpacing;
        vars.tickLower = vars.tickUpper - 1 * tickSpacing;

        // Get the original option details
        uint256 originalOptionId = 1; // Assuming this is the first option minted
        (,,,,, uint256 liquidityToUse) = optionMarketOTMFE.opTickMap(originalOptionId, 0);

        // Prepare split parameters
        uint256[] memory liquidityToSplit = new uint256[](1);
        liquidityToSplit[0] = liquidityToUse / 2;

        OptionMarketOTMFE.PositionSplitterParams memory params = OptionMarketOTMFE.PositionSplitterParams({
            optionId: originalOptionId,
            to: trader,
            liquidityToSplit: liquidityToSplit
        });

        // Split the option
        vm.startPrank(trader);
        optionMarketOTMFE.positionSplitter(params);
        uint256 newOptionId = optionMarketOTMFE.optionIds();
        vm.stopPrank();

        // Assertions
        assertEq(newOptionId, 2, "New option ID should be 2");

        // Check if the original option has reduced liquidity
        (,,,,, uint256 remainingLiquidity) = optionMarketOTMFE.opTickMap(originalOptionId, 0);
        assertGe(remainingLiquidity, liquidityToUse / 2, "Original option should have half of the original liquidity");

        // Check if new option has correct liquidity
        (,,,,, uint256 newLiquidity) = optionMarketOTMFE.opTickMap(newOptionId, 0);
        assertEq(newLiquidity, liquidityToUse / 2, "New option should have half of the original liquidity");

        // Check if new option has the same parameters as the original
        OptionMarketOTMFE.OptionData memory newOpData;
        (newOpData.opTickArrayLen, newOpData.expiry, newOpData.tickLower, newOpData.tickUpper, newOpData.isCall) =
            optionMarketOTMFE.opData(newOptionId);

        OptionMarketOTMFE.OptionData memory originalOpData;

        (
            originalOpData.opTickArrayLen,
            originalOpData.expiry,
            originalOpData.tickLower,
            originalOpData.tickUpper,
            originalOpData.isCall
        ) = optionMarketOTMFE.opData(originalOptionId);

        assertEq(newOpData.opTickArrayLen, originalOpData.opTickArrayLen, "New option should have same opTickArrayLen");
        assertEq(newOpData.tickLower, originalOpData.tickLower, "New option should have same lower tick");
        assertEq(newOpData.tickUpper, originalOpData.tickUpper, "New option should have same upper tick");
        assertEq(newOpData.expiry, originalOpData.expiry, "New option should have same expiry");
        assertEq(newOpData.isCall, originalOpData.isCall, "New option should have same isCall value");

        // Check if the trader owns the new option
        assertEq(optionMarketOTMFE.ownerOf(newOptionId), trader, "Trader should own the new option");
    }

    // Add this function to handle the swap callback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) {
            USDC.transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ETH.transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function _createSignature(
        address _user,
        uint256 _handlerIdentifierId,
        MintOptionFirewall.RangeCheckData memory _rangeData
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                mintOptionFirewall.getRangeCheckTypehash(),
                _user,
                _rangeData.pool,
                address(optionMarketOTMFE),
                _rangeData.minTickLower,
                _rangeData.maxTickUpper,
                _rangeData.minSqrtPriceX96,
                _rangeData.maxSqrtPriceX96,
                _rangeData.deadline
            )
        );

        bytes32 digest = mintOptionFirewall.hashTypedDataV4(structHash);

        return vm.sign(verifiedSignerPrivateKey, digest);
    }

    function _createSignatureExercise(
        address _user,
        uint256 _handlerIdentifierId,
        ExerciseOptionFirewall.RangeCheckData memory _rangeData
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                exerciseOptionFirewall.getRangeCheckTypehash(),
                _user,
                _rangeData.pool,
                address(optionMarketOTMFE),
                _rangeData.minTickLower,
                _rangeData.maxTickUpper,
                _rangeData.minSqrtPriceX96,
                _rangeData.maxSqrtPriceX96,
                _rangeData.deadline
            )
        );

        bytes32 digest = exerciseOptionFirewall.hashTypedDataV4(structHash);

        return vm.sign(verifiedSignerPrivateKey, digest);
    }

    function onSwapReceived(address _tokenIn, address _tokenOut, uint256 _amountIn, bytes calldata _swapData)
        public
        returns (uint256 amountOut)
    {
        if (_tokenIn == address(USDC)) {
            USDC.approve(address(pool), _amountIn);
            pool.swap(msg.sender, true, int256(_amountIn), TickMath.MIN_SQRT_RATIO + 1, abi.encode(address(this)));
        } else if (_tokenIn == address(ETH)) {
            ETH.approve(address(pool), _amountIn);
            pool.swap(msg.sender, false, int256(_amountIn), TickMath.MAX_SQRT_RATIO - 1, abi.encode(address(this)));
        }
    }
}
