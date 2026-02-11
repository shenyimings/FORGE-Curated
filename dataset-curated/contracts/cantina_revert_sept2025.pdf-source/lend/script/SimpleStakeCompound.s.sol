// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/transformers/V3Utils.sol";

interface IGaugeManager {
    function stakePosition(uint256 tokenId) external;
    function unstakePosition(uint256 tokenId) external;
    function compoundRewards(
        uint256 tokenId,
        bytes memory swapData0,
        bytes memory swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 aeroSplitBps,
        uint256 deadline
    ) external;
    function claimRewards(uint256 tokenId) external;
    function tokenIdToGauge(uint256 tokenId) external view returns (address);
    function positionOwners(uint256 tokenId) external view returns (address);
    
    
    function executeV3UtilsWithOptionalCompound(
        uint256 tokenId,
        address v3utils,
        V3Utils.Instructions memory instructions,
        bool shouldCompound,
        bytes memory aeroSwapData0,
        bytes memory aeroSwapData1,
        uint256 minAeroAmount0,
        uint256 minAeroAmount1,
        uint256 aeroSplitBps
    ) external returns (uint256 newTokenId);
    
    function swapAndIncreaseStakedPosition(
        uint256 tokenId,
        address v3utils,
        V3Utils.SwapAndIncreaseLiquidityParams calldata params
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IGauge {
    function earned(address account, uint256 tokenId) external view returns (uint256);
}

interface INPM {
    function approve(address spender, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    
    // Get position details
    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );
    
    struct MintParams {
        address token0;
        address token1;
        uint24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
        uint160 sqrtPriceX96;
    }
    
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    
    // Mint a new position
    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    
    // Increase liquidity in existing position
    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
}

interface IPool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

interface IAerodromeFactory {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}

interface IWETH {
    function deposit() external payable;
}

contract SimpleStakeCompound is Script {
    // Deployed contracts on Base (Latest deployment: 2025-09-06)
    address constant GAUGE_MANAGER = 0x3a9cB8c9b358eD3bC44A539B9Bb356Fe64b08559;
    address constant NPM = 0x827922686190790b37229fd06084350E74485b72;
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant AERODROME_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address payable constant V3_UTILS = payable(0x7D1F9FC22beD0798cDA3Fdb18b14a96fc838B9E1);
    
    // Token addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    /// @notice Calculate optimal aeroSplitBps based on position state
    /// @param tokenId The position to analyze
    /// @return aeroSplitBps The optimal basis points to swap to token0
    function calculateOptimalSplit(uint256 tokenId) public view returns (uint256 aeroSplitBps) {
        // Get position details
        (,, address token0, address token1, uint24 tickSpacing, int24 tickLower, int24 tickUpper,,,,,) = 
            INPM(NPM).positions(tokenId);
        
        // Get pool address
        address pool = IAerodromeFactory(AERODROME_FACTORY).getPool(token0, token1, int24(tickSpacing));
        require(pool != address(0), "Pool not found");
        
        // Get current tick
        (,int24 currentTick,,,,,) = IPool(pool).slot0();
        
        // Calculate optimal split based on position in range
        if (currentTick >= tickUpper) {
            // Position is all in token0, need 100% token0
            return 10000;
        } else if (currentTick <= tickLower) {
            // Position is all in token1, need 100% token1
            return 0;
        } else {
            // Linear interpolation: the higher we are in the range, the more token0 we need
            uint256 tickRange = uint256(int256(tickUpper - tickLower));
            uint256 tickPosition = uint256(int256(currentTick - tickLower));
            
            // Calculate percentage through range (0 to 10000 bps)
            return (tickPosition * 10000) / tickRange;
        }
    }
    
    /// @notice Stake your Aerodrome position NFT
    function stake(uint256 tokenId) external {
        vm.startBroadcast();
        
        // Approve GaugeManager to take your NFT
        INPM(NPM).approve(GAUGE_MANAGER, tokenId);
        
        // Stake it
        IGaugeManager(GAUGE_MANAGER).stakePosition(tokenId);
        
        vm.stopBroadcast();
        
        console.log("Position", tokenId, "staked successfully!");
    }
    
    /// @notice Compound your AERO rewards back into the position with intelligent split
    function compound(uint256 tokenId) external {
        // First calculate the optimal split based on position state
        uint256 aeroSplitBps = calculateOptimalSplit(tokenId);
        
        console.log("Position", tokenId, "optimal AERO split:");
        console.log("  - Token0:", aeroSplitBps / 100, "%");
        console.log("  - Token1:", (10000 - aeroSplitBps) / 100, "%");
        
        vm.startBroadcast();
        
        // Swap data (router will handle the actual swap logic)
        // In production, you'd fetch real 0x quotes here
        bytes memory swapData0 = abi.encode(UNIVERSAL_ROUTER, hex"");
        bytes memory swapData1 = abi.encode(UNIVERSAL_ROUTER, hex"");
        
        // Compound with calculated optimal split
        IGaugeManager(GAUGE_MANAGER).compoundRewards(
            tokenId,
            swapData0,
            swapData1,
            0, // minAmount0 - should calculate based on 0x quote
            0, // minAmount1 - should calculate based on 0x quote
            aeroSplitBps, // Use calculated optimal split
            block.timestamp + 300 // 5 minutes
        );
        
        vm.stopBroadcast();
        
        console.log("Rewards compounded for position", tokenId, "with optimal split!");
    }
    
    /// @notice Claim AERO rewards without compounding (for debugging)
    function claim(uint256 tokenId) external {
        vm.startBroadcast();
        
        IGaugeManager(GAUGE_MANAGER).claimRewards(tokenId);
        
        vm.stopBroadcast();
        
        console.log("Rewards claimed for position", tokenId);
    }
    
    /// @notice Unstake your position and get the NFT back
    function unstake(uint256 tokenId) external {
        vm.startBroadcast();
        
        // Unstake the position - this will:
        // 1. Claim any pending AERO rewards and send them to the owner
        // 2. Return the NFT back to the original owner
        IGaugeManager(GAUGE_MANAGER).unstakePosition(tokenId);
        
        vm.stopBroadcast();
        
        console.log("Position", tokenId, "unstaked successfully!");
        console.log("NFT returned to owner and rewards claimed");
    }
    
    /// @notice Check pending AERO rewards for a position
    /// @param tokenId The position to check
    function checkRewards(uint256 tokenId) external view {
        console.log("Checking rewards for position...");
        
        address gauge = IGaugeManager(GAUGE_MANAGER).tokenIdToGauge(tokenId);
        console.log("Gauge address:");
        console.logAddress(gauge);
        
        if (gauge == address(0)) {
            console.log("ERROR: Position not staked");
            return;
        }
        
        uint256 pending = IGauge(gauge).earned(GAUGE_MANAGER, tokenId);
        
        // Convert to smaller units to avoid console.log issues with large numbers
        uint256 pendingInGwei = pending / 1e9;
        uint256 pendingInFinney = pending / 1e15;
        
        console.log("==========================================");
        console.log("POSITION REWARDS INFO");
        console.log("==========================================");
        console.log("Pending (in gwei):", pendingInGwei);
        console.log("Pending (in finney):", pendingInFinney);
        console.log("Has rewards:", pending > 0);
        
        // Show approximate AERO amount
        if (pending > 1e16) {
            console.log("Approximately 0.01+ AERO");
        } else if (pending > 1e15) {
            console.log("Approximately 0.001+ AERO");
        } else if (pending > 1e14) {
            console.log("Approximately 0.0001+ AERO");
        } else if (pending > 0) {
            console.log("Less than 0.0001 AERO");
        } else {
            console.log("No pending rewards");
        }
        console.log("==========================================");
    }
    
    /// @notice Compound with actual 0x swap data
    /// @param tokenId The position to compound
    /// @param swapData0 The 0x swap data for AERO -> token0
    /// @param swapData1 The 0x swap data for AERO -> token1
    /// @param minAmount0 Minimum amount of token0 expected
    /// @param minAmount1 Minimum amount of token1 expected
    /// @param aeroSplitBps Basis points of AERO to swap to token0 (e.g., 6000 = 60%)
    function compoundWith0x(
        uint256 tokenId,
        bytes calldata swapData0,
        bytes calldata swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 aeroSplitBps
    ) external {
        vm.startBroadcast();
        
        console.log("Compounding position", tokenId, "with 0x swap data");
        console.log("Min amount token0:", minAmount0);
        console.log("Min amount token1:", minAmount1);
        
        // Execute compound with the provided 0x swap data
        IGaugeManager(GAUGE_MANAGER).compoundRewards(
            tokenId,
            swapData0,
            swapData1,
            minAmount0,
            minAmount1,
            aeroSplitBps,
            block.timestamp + 1200 // 20 minutes deadline
        );
        
        vm.stopBroadcast();
        
        console.log("Compound executed with 0x data!");
    }
    
    /// @notice Change range with optional AERO compounding using 0x swap data
    /// @param tokenId The position to change range for
    /// @param newTickLower The new lower tick bound (or 0 to expand by tick spacing)
    /// @param newTickUpper The new upper tick bound (or 0 to expand by tick spacing)
    /// @param swapData0 The 0x swap data for AERO -> token0 (if compounding)
    /// @param swapData1 The 0x swap data for AERO -> token1 (if compounding)
    /// @param minAmount0 Minimum amount of token0 expected from AERO swap
    /// @param minAmount1 Minimum amount of token1 expected from AERO swap
    /// @param aeroSplitBps Basis points of AERO to swap to token0
    /// @param shouldCompound Whether to compound AERO rewards
    function changeRangeWith0x(
        uint256 tokenId,
        int24 newTickLower,
        int24 newTickUpper,
        bytes calldata swapData0,
        bytes calldata swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 aeroSplitBps,
        bool shouldCompound
    ) external {
        // Get position details
        (,, address token0, address token1, uint24 tickSpacing, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
            INPM(NPM).positions(tokenId);
        
        // If new ticks are 0, expand by tick spacing
        if (newTickLower == 0 && newTickUpper == 0) {
            newTickLower = tickLower - int24(tickSpacing);
            newTickUpper = tickUpper + int24(tickSpacing);
            console.log("Expanding range by tick spacing");
        }
        
        vm.startBroadcast();
        
        console.log("Changing range for position", tokenId);
        console.log("Old tick lower:", uint256(int256(tickLower)));
        console.log("Old tick upper:", uint256(int256(tickUpper)));
        console.log("New tick lower:", uint256(int256(newTickLower)));
        console.log("New tick upper:", uint256(int256(newTickUpper)));
        console.log("Should compound:", shouldCompound);
        
        if (shouldCompound) {
            console.log("WARNING: AERO compounding temporarily disabled in changeRangeWith0x");
            console.log("         Use executeV3UtilsWithOptionalCompound for full control");
        }
        
        // Execute range change with optional AERO compounding
        // Note: v3SwapData0/1 are for position token swaps, not AERO swaps
        // Build V3Utils instructions for CHANGE_RANGE
        V3Utils.Instructions memory instructions = V3Utils.Instructions({
            whatToDo: V3Utils.WhatToDo.CHANGE_RANGE,
            targetToken: address(0), // No rebalancing
            amountRemoveMin0: 0,
            amountRemoveMin1: 0,
            amountIn0: 0,
            amountOut0Min: 0,
            swapData0: "", // No swaps
            amountIn1: 0,
            amountOut1Min: 0,
            swapData1: "", // No swaps
            feeAmount0: type(uint128).max, // Collect all fees
            feeAmount1: type(uint128).max, // Collect all fees
            fee: tickSpacing,
            tickLower: newTickLower,
            tickUpper: newTickUpper,
            liquidity: liquidity, // Remove all current liquidity
            amountAddMin0: 0,
            amountAddMin1: 0,
            deadline: block.timestamp + 1200,
            recipient: IGaugeManager(GAUGE_MANAGER).positionOwners(tokenId),
            recipientNFT: address(GAUGE_MANAGER),
            unwrap: false,
            returnData: "",
            swapAndMintReturnData: ""
        });
        
        uint256 newTokenId = IGaugeManager(GAUGE_MANAGER).executeV3UtilsWithOptionalCompound(
            tokenId,
            V3_UTILS,
            instructions,
            false, // Disable compounding for now
            "", // aeroSwapData0
            "", // aeroSwapData1
            0, // minAeroAmount0
            0, // minAeroAmount1
            aeroSplitBps // Will be used if/when we enable compounding
        );
        
        vm.stopBroadcast();
        
        console.log("Range change executed!");
        if (newTokenId != tokenId) {
            console.log("New token ID:", newTokenId);
        }
    }
    
    /// @notice Advanced change range with full AERO compounding support
    /// @param tokenId The position to change range for
    /// @param newTickLower The new lower tick bound (or 0 to expand by tick spacing)
    /// @param newTickUpper The new upper tick bound (or 0 to expand by tick spacing)
    /// @param swapData0 The 0x swap data for AERO -> token0 (if compounding)
    /// @param swapData1 The 0x swap data for AERO -> token1 (if compounding)
    /// @param minAmount0 Minimum amount of token0 expected from AERO swap
    /// @param minAmount1 Minimum amount of token1 expected from AERO swap
    /// @param aeroSplitBps Basis points of AERO to swap to token0
    /// @param shouldCompound Whether to compound AERO rewards
    function changeRangeWithAeroCompound(
        uint256 tokenId,
        int24 newTickLower,
        int24 newTickUpper,
        bytes calldata swapData0,
        bytes calldata swapData1,
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 aeroSplitBps,
        bool shouldCompound
    ) external {
        // Get position details
        (,, address token0, address token1, uint24 tickSpacing, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
            INPM(NPM).positions(tokenId);
        
        // If new ticks are 0, expand by tick spacing
        if (newTickLower == 0 && newTickUpper == 0) {
            newTickLower = tickLower - int24(tickSpacing);
            newTickUpper = tickUpper + int24(tickSpacing);
            console.log("Expanding range by tick spacing");
        }
        
        // Build V3Utils instructions for CHANGE_RANGE
        V3Utils.Instructions memory instructions = V3Utils.Instructions({
            whatToDo: V3Utils.WhatToDo.CHANGE_RANGE,
            targetToken: address(0), // No rebalancing
            amountRemoveMin0: 0,
            amountRemoveMin1: 0,
            amountIn0: 0,
            amountOut0Min: 0,
            swapData0: "", // No position token swaps
            amountIn1: 0,
            amountOut1Min: 0,
            swapData1: "", // No position token swaps
            feeAmount0: type(uint128).max, // Collect all fees
            feeAmount1: type(uint128).max, // Collect all fees
            fee: tickSpacing, // Keep same fee tier
            tickLower: newTickLower,
            tickUpper: newTickUpper,
            liquidity: liquidity, // Remove all current liquidity to move to new position
            amountAddMin0: 0,
            amountAddMin1: 0,
            deadline: block.timestamp + 1200,
            recipient: msg.sender, // Send dust to caller
            recipientNFT: GAUGE_MANAGER, // New NFT goes to GaugeManager
            unwrap: false,
            returnData: "",
            swapAndMintReturnData: ""
        });
        
        vm.startBroadcast();
        
        console.log("Changing range for position", tokenId, "with AERO compound support");
        console.log("Old tick lower:", uint256(int256(tickLower)));
        console.log("Old tick upper:", uint256(int256(tickUpper)));
        console.log("New tick lower:", uint256(int256(newTickLower)));
        console.log("New tick upper:", uint256(int256(newTickUpper)));
        console.log("Should compound:", shouldCompound);
        
        // Execute with proper AERO compounding support
        uint256 newTokenId = IGaugeManager(GAUGE_MANAGER).executeV3UtilsWithOptionalCompound(
            tokenId,
            V3_UTILS,
            instructions,
            shouldCompound,
            swapData0, // AERO -> token0 swap data
            swapData1, // AERO -> token1 swap data
            minAmount0, // Min token0 from AERO
            minAmount1, // Min token1 from AERO
            aeroSplitBps
        );
        
        vm.stopBroadcast();
        
        console.log("Range change executed with AERO compounding!");
        if (newTokenId != tokenId) {
            console.log("New token ID:", newTokenId);
        }
    }
    
    /// @notice Shift position by tick spacing with V3Utils swap support
    /// @param tokenId The position to shift
    /// @param shiftUp Whether to shift up (true) or down (false)
    /// @param targetToken Target token for V3Utils swap (address(0) = no swap)
    /// @param v3SwapData Swap data for V3Utils rebalancing
    /// @param swapAmount The exact amount to swap
    /// @param aeroSplitBps Basis points of AERO to swap to token0 (not used here but kept for consistency)
    function shiftPositionWithSwap(
        uint256 tokenId,
        bool shiftUp,
        address targetToken,
        bytes calldata v3SwapData,
        uint256 swapAmount,
        uint256 aeroSplitBps
    ) external {
        vm.startBroadcast();
        
        // Get position details
        (,, address token0, address token1, uint24 tickSpacing, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) = 
            INPM(NPM).positions(tokenId);
        
        // Calculate new ticks - shift by tickSpacing
        int24 newTickLower = shiftUp ? tickLower + int24(tickSpacing) : tickLower - int24(tickSpacing);
        int24 newTickUpper = shiftUp ? tickUpper + int24(tickSpacing) : tickUpper - int24(tickSpacing);
        
        console.log(string.concat("Shifting position ", shiftUp ? "UP" : "DOWN", " by tick spacing"));
        console.log("Current range:");
        console.logInt(tickLower);
        console.log(" to ");
        console.logInt(tickUpper);
        console.log("New range:");
        console.logInt(newTickLower);
        console.log(" to ");
        console.logInt(newTickUpper);
        
        // Determine swap parameters based on direction and target token
        uint256 amountIn0 = 0;
        uint256 amountIn1 = 0;
        bytes memory swapData0 = "";
        bytes memory swapData1 = "";
        
        if (targetToken == token0) {
            // Swapping token1 -> token0
            amountIn1 = swapAmount;
            swapData1 = v3SwapData;
        } else if (targetToken == token1) {
            // Swapping token0 -> token1
            amountIn0 = swapAmount;
            swapData0 = v3SwapData;
        }
        
        // Build V3Utils instructions for CHANGE_RANGE
        V3Utils.Instructions memory instructions = V3Utils.Instructions({
            whatToDo: V3Utils.WhatToDo.CHANGE_RANGE,
            targetToken: targetToken,
            amountRemoveMin0: 0,
            amountRemoveMin1: 0,
            amountIn0: amountIn0,
            amountOut0Min: 0,
            swapData0: swapData0,
            amountIn1: amountIn1,
            amountOut1Min: 0,
            swapData1: swapData1,
            feeAmount0: type(uint128).max, // Collect all fees
            feeAmount1: type(uint128).max, // Collect all fees
            fee: tickSpacing,
            tickLower: newTickLower,
            tickUpper: newTickUpper,
            liquidity: liquidity, // Remove all liquidity from old position
            amountAddMin0: 0,
            amountAddMin1: 0,
            deadline: block.timestamp + 1200,
            recipient: msg.sender, // Send dust to owner
            recipientNFT: GAUGE_MANAGER, // New NFT goes to GaugeManager
            unwrap: false,
            returnData: "",
            swapAndMintReturnData: ""
        });
        
        // Execute via GaugeManager - no AERO compounding for shift operations
        uint256 newTokenId = IGaugeManager(GAUGE_MANAGER).executeV3UtilsWithOptionalCompound(
            tokenId,
            V3_UTILS,
            instructions,
            false, // No AERO compounding
            "", // No AERO swap data
            "", // No AERO swap data
            0,  // No min amounts
            0,  // No min amounts
            aeroSplitBps // Not used but required by interface
        );
        
        vm.stopBroadcast();
        
        console.log("Position shifted successfully!");
        if (newTokenId != tokenId) {
            console.log("New token ID:", newTokenId);
        }
    }
}

/**
 * SIMPLE USAGE:
 * 
 * 1. Stake position 12345:
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "stake(uint256)" 12345 \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 * 
 * 2. Check pending rewards (view only):
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "checkRewards(uint256)" 12345 \
 *      --rpc-url $ETH_RPC_URL
 * 
 * 3. Claim rewards only (for debugging):
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "claim(uint256)" 12345 \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 * 
 * 4. Compound rewards with automatic optimal split calculation:
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "compound(uint256)" 12345 \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 * 
 *    This will:
 *    - Calculate the position's current state
 *    - Determine optimal AERO split based on tick position
 *    - Compound with the calculated split ratio
 * 
 * 5. Unstake position and get NFT back:
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "unstake(uint256)" 12345 \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 * 
 * 6. Compound with 0x swap data:
 *    
 *    First, get swap data from 0x API:
 *    
 *    For AERO -> WETH:
 *    curl "https://base.api.0x.org/swap/v1/quote?sellToken=0x940181a94A35A4569E4529A3CDfB74e38FD98631&buyToken=0x4200000000000000000000000000000000000006&sellAmount=AMOUNT&takerAddress=0x6EEEE423297481Ce9e4e007E191e789eD3B4dA21" \
 *      -H "0x-api-key: YOUR_API_KEY"
 *    
 *    For AERO -> USDC:
 *    curl "https://base.api.0x.org/swap/v1/quote?sellToken=0x940181a94A35A4569E4529A3CDfB74e38FD98631&buyToken=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913&sellAmount=AMOUNT&takerAddress=0x6EEEE423297481Ce9e4e007E191e789eD3B4dA21" \
 *      -H "0x-api-key: YOUR_API_KEY"
 *    
 *    Then use the "data" field from each response:
 *    
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "compoundWith0x(uint256,bytes,bytes,uint256,uint256,uint256)" \
 *      12345 \
 *      0xDATA_FROM_0X_FOR_TOKEN0 \
 *      0xDATA_FROM_0X_FOR_TOKEN1 \
 *      MIN_AMOUNT_TOKEN0 \
 *      MIN_AMOUNT_TOKEN1 \
 *      5000 \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 * 
 * 7. Change range with optional AERO compounding:
 *    
 *    Without compounding (just expand range by tick spacing):
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "changeRangeWith0x(uint256,int24,int24,bytes,bytes,uint256,uint256,uint256,bool)" \
 *      12345 \
 *      0 \
 *      0 \
 *      0x \
 *      0x \
 *      0 \
 *      0 \
 *      5000 \
 *      false \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 *    
 *    With AERO compounding (use Python wrapper script instead):
 *    python scripts/test_change_range.py 12345 --compound
 * 
 * 8. Change range with full AERO compounding support:
 *    
 *    Use the Python wrapper script which will call changeRangeWithAeroCompound:
 *    python scripts/test_change_range.py 12345 --compound
 *    
 *    Or manually with forge (get swap data from 0x API first):
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "changeRangeWithAeroCompound(uint256,int24,int24,bytes,bytes,uint256,uint256,uint256,bool)" \
 *      12345 \
 *      0 \
 *      0 \
 *      0xAERO_TO_TOKEN0_SWAP_DATA \
 *      0xAERO_TO_TOKEN1_SWAP_DATA \
 *      MIN_TOKEN0_AMOUNT \
 *      MIN_TOKEN1_AMOUNT \
 *      5000 \
 *      true \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 * 
 * 9. Deposit ETH to position:
 *    
 *    # Create new position with 0.5 ETH
 *    forge script script/SimpleStakeCompound.s.sol:SimpleStakeCompound \
 *      --sig "depositETHToPosition(uint256,int24,int24,uint24,bytes,uint256,bool)" \
 *      0 \
 *      -192000 \
 *      -191000 \
 *      10 \
 *      0xSWAP_DATA_FROM_0X \
 *      250000000000000000 \
 *      true \
 *      --value 500000000000000000 \
 *      --rpc-url $ETH_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --broadcast
 *    
 *    # Or use the Python wrapper for easier execution:
 *    python scripts/deposit_eth_to_position.py 0.5
 *    python scripts/deposit_eth_to_position.py 1.0 --token-id 12345
 *    python scripts/deposit_eth_to_position.py 0.1 --tick-lower -192000 --tick-upper -191000 --no-stake
 */
