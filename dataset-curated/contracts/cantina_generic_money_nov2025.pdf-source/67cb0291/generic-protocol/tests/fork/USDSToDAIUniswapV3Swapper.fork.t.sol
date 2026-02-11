// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import {
    USDSToDAIUniswapV3Swapper,
    IUniswapSwapRouterLike,
    IUniswapQuoterLike,
    IDaiUsdsConverter,
    IERC20
} from "../../src/periphery/swapper/USDSToDAIUniswapV3Swapper.sol";

abstract contract USDSToDAIUniswapV3SwapperForkTest is Test {
    IUniswapSwapRouterLike constant SWAP_ROUTER = IUniswapSwapRouterLike(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapQuoterLike constant QUOTER = IUniswapQuoterLike(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IDaiUsdsConverter constant DAI_USDS_CONVERTER = IDaiUsdsConverter(0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A);

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    USDSToDAIUniswapV3Swapper swapper;

    address user = makeAddr("user");

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        swapper = new USDSToDAIUniswapV3Swapper(SWAP_ROUTER, QUOTER, DAI_USDS_CONVERTER, address(DAI), address(USDS));
    }
}

contract USDSToDAIUniswapV3Swapper_Swap_ForkTest is USDSToDAIUniswapV3SwapperForkTest {
    function test_shouldSwapUSDStoUSDT() public {
        uint256 amountIn = 10_000e18;
        uint24 fee = 100;
        uint256 minAmountOut = swapper.getAmountOut(address(USDS), amountIn, address(USDT), abi.encode(fee));

        deal(address(USDS), user, amountIn);
        vm.prank(user);
        require(USDS.transfer(address(swapper), amountIn));

        uint256 balanceBefore = USDT.balanceOf(user);
        vm.expectCall(
            address(SWAP_ROUTER),
            abi.encodeWithSelector(
                IUniswapSwapRouterLike.exactInputSingle.selector,
                IUniswapSwapRouterLike.ExactInputSingleParams({
                    tokenIn: address(DAI), // because USDS is converted to DAI first
                    tokenOut: address(USDT),
                    fee: fee,
                    recipient: user, // because recipient is forwarded from swap()
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        uint256 amountOut = swapper.swap(address(USDS), amountIn, address(USDT), minAmountOut, user, abi.encode(fee));
        uint256 balanceAfter = USDT.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, amountOut);
        assertApproxEqRel(amountIn / 1e12, amountOut, 1e16); // 1% slippage between stable pairs
        assertGe(amountOut, minAmountOut);
    }

    function test_shouldSwapUSDTtoUSDS() public {
        uint256 amountIn = 10_000e6;
        uint24 fee = 100;
        uint256 minAmountOut = swapper.getAmountOut(address(USDT), amountIn, address(USDS), abi.encode(fee));

        deal(address(USDT), address(swapper), amountIn); // deal to user and then transfer fails

        uint256 balanceBefore = USDS.balanceOf(user);
        vm.expectCall(
            address(SWAP_ROUTER),
            abi.encodeWithSelector(
                IUniswapSwapRouterLike.exactInputSingle.selector,
                IUniswapSwapRouterLike.ExactInputSingleParams({
                    tokenIn: address(USDT),
                    tokenOut: address(DAI), // because swap is to DAI first
                    fee: fee,
                    recipient: address(swapper), // because DAI is converted to USDS next
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        uint256 amountOut = swapper.swap(address(USDT), amountIn, address(USDS), minAmountOut, user, abi.encode(fee));
        uint256 balanceAfter = USDS.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, amountOut);
        assertApproxEqRel(amountIn * 1e12, amountOut, 1e16); // 1% slippage between stable pairs
        assertGe(amountOut, minAmountOut);
    }
}
