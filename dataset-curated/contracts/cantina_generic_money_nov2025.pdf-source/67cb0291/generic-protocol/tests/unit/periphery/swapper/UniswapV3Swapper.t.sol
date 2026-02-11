// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import {
    UniswapV3Swapper,
    IUniswapSwapRouterLike,
    IUniswapQuoterLike,
    IERC20,
    ISwapper
} from "../../../../src/periphery/swapper/UniswapV3Swapper.sol";

abstract contract UniswapV3SwapperTest is Test {
    UniswapV3Swapper swapper;

    address uniswapRouter = makeAddr("uniswapRouter");
    address quoter = makeAddr("quoter");
    address assetIn = makeAddr("assetIn");
    address assetOut = makeAddr("assetOut");
    uint256 amountIn = 1e18;
    uint256 minAmountOut = 1e18;
    uint256 amountOut = 1e18;
    address recipient = makeAddr("recipient");
    uint24 fee = 3000;

    function setUp() public virtual {
        swapper = new UniswapV3Swapper(IUniswapSwapRouterLike(uniswapRouter), IUniswapQuoterLike(quoter));

        vm.mockCall(assetIn, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(
            uniswapRouter,
            abi.encodeWithSelector(IUniswapSwapRouterLike.exactInputSingle.selector),
            abi.encode(amountOut)
        );
        vm.mockCall(
            quoter, abi.encodeWithSelector(IUniswapQuoterLike.quoteExactInputSingle.selector), abi.encode(amountOut)
        );
    }
}

contract UniswapV3Swapper_Swap_Test is UniswapV3SwapperTest {
    function test_shouldRevert_whenAssetInIsZeroAddress() public {
        vm.expectRevert(UniswapV3Swapper.ZeroAddress.selector);
        swapper.swap(address(0), amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldRevert_whenAssetOutIsZeroAddress() public {
        vm.expectRevert(UniswapV3Swapper.ZeroAddress.selector);
        swapper.swap(assetIn, amountIn, address(0), minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldRevert_whenAssetInEqualsAssetOut() public {
        vm.expectRevert(UniswapV3Swapper.IdenticalAddresses.selector);
        swapper.swap(assetIn, amountIn, assetIn, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldRevert_whenAmountInIsZero() public {
        vm.expectRevert(UniswapV3Swapper.InsufficientInputAmount.selector);
        swapper.swap(assetIn, 0, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldRevert_whenMintAmountOutIsZero() public {
        vm.expectRevert(UniswapV3Swapper.InsufficientOutputAmount.selector);
        swapper.swap(assetIn, amountIn, assetOut, 0, recipient, abi.encode(fee));
    }

    function test_shouldApproveAssetInToUniswapRouter() public {
        vm.expectCall(assetIn, abi.encodeWithSelector(IERC20.approve.selector, uniswapRouter, amountIn));

        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldCallUniswapRouterExactInputSingle_withCorrectParams() public {
        vm.expectCall(
            uniswapRouter,
            abi.encodeWithSelector(
                IUniswapSwapRouterLike.exactInputSingle.selector,
                IUniswapSwapRouterLike.ExactInputSingleParams({
                    tokenIn: assetIn,
                    tokenOut: assetOut,
                    fee: fee,
                    recipient: recipient,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            )
        );

        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldRevert_whenAmountOutIsLessThanMinAmountOut() public {
        vm.mockCall(
            uniswapRouter,
            abi.encodeWithSelector(IUniswapSwapRouterLike.exactInputSingle.selector),
            abi.encode(minAmountOut - 1)
        );

        vm.expectRevert(UniswapV3Swapper.InsufficientOutputAmount.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldReturnAmountOut() public {
        uint256 result = swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
        assertEq(result, amountOut);
    }

    function test_shouldEmit_Swap() public {
        vm.expectEmit();
        emit ISwapper.Swap(assetIn, assetOut, amountIn, amountOut);

        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }
}

contract UniswapV3Swapper_GetAmountOut_Test is UniswapV3SwapperTest {
    function test_shouldCallQuoterQuoteExactInputSingle_withCorrectParams() public {
        vm.expectCall(
            quoter,
            abi.encodeWithSelector(
                IUniswapQuoterLike.quoteExactInputSingle.selector, assetIn, assetOut, fee, amountIn, 0
            )
        );

        swapper.getAmountOut(assetIn, amountIn, assetOut, abi.encode(fee));
    }

    function test_shouldReturnAmountOut() public {
        uint256 result = swapper.getAmountOut(assetIn, amountIn, assetOut, abi.encode(fee));
        assertEq(result, amountOut);
    }
}
