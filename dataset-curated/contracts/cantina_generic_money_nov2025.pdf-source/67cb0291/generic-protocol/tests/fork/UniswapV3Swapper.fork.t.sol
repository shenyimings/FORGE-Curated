// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import {
    UniswapV3Swapper,
    IUniswapSwapRouterLike,
    IUniswapQuoterLike,
    IERC20
} from "../../src/periphery/swapper/UniswapV3Swapper.sol";

abstract contract UniswapV3SwapperForkTest is Test {
    IUniswapSwapRouterLike constant SWAP_ROUTER = IUniswapSwapRouterLike(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapQuoterLike constant QUOTER = IUniswapQuoterLike(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    UniswapV3Swapper swapper;

    address user = makeAddr("user");

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        swapper = new UniswapV3Swapper(SWAP_ROUTER, QUOTER);
    }
}

contract UniswapV3Swapper_Swap_ForkTest is UniswapV3SwapperForkTest {
    function test_shouldSwapUSDCtoUSDT_whenNoSlippage() public {
        uint256 amountIn = 1000e6;
        uint256 fee = 100;
        uint256 minAmountOut = swapper.getAmountOut(address(USDC), amountIn, address(USDT), abi.encode(fee));

        deal(address(USDC), user, amountIn);
        vm.prank(user);
        require(USDC.transfer(address(swapper), amountIn));

        uint256 balanceBefore = USDT.balanceOf(user);
        uint256 amountOut = swapper.swap(address(USDC), amountIn, address(USDT), minAmountOut, user, abi.encode(fee));
        uint256 balanceAfter = USDT.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, amountOut);
        assertGe(amountOut, minAmountOut);
    }

    function test_shouldRevert_whenSwapUSDCtoUSDT_whenSlippageOverLimit() public {
        uint256 amountIn = 1000e6;
        uint256 fee = 100;
        uint256 minAmountOut = swapper.getAmountOut(address(USDC), amountIn, address(USDT), abi.encode(fee));
        minAmountOut = minAmountOut * 9999 / 10_000; // 0.01% slippage

        // Move market to create slippage
        address attacker = makeAddr("attacker");
        uint256 largeAmountIn = 5_000_000e6;
        deal(address(USDC), attacker, largeAmountIn);
        vm.prank(attacker);
        require(USDC.transfer(address(swapper), largeAmountIn));
        swapper.swap(address(USDC), largeAmountIn, address(USDT), 1, user, abi.encode(fee));

        // Try swap with slippage protection
        deal(address(USDC), user, amountIn);
        vm.prank(user);
        require(USDC.transfer(address(swapper), amountIn));

        vm.expectRevert();
        swapper.swap(address(USDC), amountIn, address(USDT), minAmountOut, user, abi.encode(fee));
    }

    function test_shouldRevert_whenPoolDoesNotExist() public {
        vm.expectRevert();
        swapper.swap(address(USDC), 1, address(USDT), 1, user, abi.encode(110)); // non-existent pool fee tier
    }
}
