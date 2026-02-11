// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import {
    USDSToDAIUniswapV3Swapper,
    UniswapV3Swapper,
    IUniswapSwapRouterLike,
    IUniswapQuoterLike,
    IDaiUsdsConverter,
    IERC20
} from "../../../../src/periphery/swapper/USDSToDAIUniswapV3Swapper.sol";

abstract contract USDSToDAIUniswapV3SwapperTest is Test {
    USDSToDAIUniswapV3Swapper swapper;

    address uniswapRouter = makeAddr("uniswapRouter");
    address quoter = makeAddr("quoter");
    address daiToUsdsConverter = makeAddr("daiToUsdsConverter");
    address dai = makeAddr("dai");
    address usds = makeAddr("usds");
    address assetIn = makeAddr("assetIn");
    address assetOut = makeAddr("assetOut");
    uint256 amountIn = 1e18;
    uint256 minAmountOut = 1e18;
    uint256 amountOut = 1e18;
    address recipient = makeAddr("recipient");
    uint24 fee = 3000;

    function setUp() public virtual {
        swapper = new USDSToDAIUniswapV3Swapper(
            IUniswapSwapRouterLike(uniswapRouter),
            IUniswapQuoterLike(quoter),
            IDaiUsdsConverter(daiToUsdsConverter),
            dai,
            usds
        );

        vm.mockCall(assetIn, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(usds, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(dai, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(
            uniswapRouter,
            abi.encodeWithSelector(IUniswapSwapRouterLike.exactInputSingle.selector),
            abi.encode(amountOut)
        );
        vm.mockCall(
            quoter, abi.encodeWithSelector(IUniswapQuoterLike.quoteExactInputSingle.selector), abi.encode(amountOut)
        );
        vm.mockCall(daiToUsdsConverter, abi.encodeWithSelector(IDaiUsdsConverter.daiToUsds.selector), "");
        vm.mockCall(daiToUsdsConverter, abi.encodeWithSelector(IDaiUsdsConverter.usdsToDai.selector), "");
    }
}

contract USDSToDAIUniswapV3Swapper_Swap_Test is USDSToDAIUniswapV3SwapperTest {
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

    function test_shouldRevert_whenBothAssetsAreUSDS() public {
        vm.expectRevert(USDSToDAIUniswapV3Swapper.BothAssetsUSDS.selector);
        swapper.swap(usds, amountIn, usds, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldRevert_whenAmountInIsZero() public {
        vm.expectRevert(UniswapV3Swapper.InsufficientInputAmount.selector);
        swapper.swap(assetIn, 0, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldConvertToDAI_whenUSDSAssetIn() public {
        vm.expectCall(usds, abi.encodeWithSelector(IERC20.approve.selector, daiToUsdsConverter, amountIn));
        vm.expectCall(
            daiToUsdsConverter, abi.encodeWithSelector(IDaiUsdsConverter.usdsToDai.selector, address(swapper), amountIn)
        );

        swapper.swap(usds, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldConvertToUSDS_whenUSDSAssetOut() public {
        vm.expectCall(dai, abi.encodeWithSelector(IERC20.approve.selector, daiToUsdsConverter, amountOut));
        vm.expectCall(
            daiToUsdsConverter, abi.encodeWithSelector(IDaiUsdsConverter.daiToUsds.selector, recipient, amountOut)
        );

        swapper.swap(assetIn, amountIn, usds, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldCallUniswapRouterExactInputSingle_whenUSDSAssetIn() public {
        vm.expectCall(
            uniswapRouter,
            abi.encodeWithSelector(
                IUniswapSwapRouterLike.exactInputSingle.selector,
                IUniswapSwapRouterLike.ExactInputSingleParams({
                    tokenIn: dai, // DAI after conversion
                    tokenOut: assetOut,
                    fee: fee,
                    recipient: recipient, // directly to recipient
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            )
        );

        swapper.swap(usds, amountIn, assetOut, minAmountOut, recipient, abi.encode(fee));
    }

    function test_shouldCallUniswapRouterExactInputSingle_whenUSDSAssetOut() public {
        vm.expectCall(
            uniswapRouter,
            abi.encodeWithSelector(
                IUniswapSwapRouterLike.exactInputSingle.selector,
                IUniswapSwapRouterLike.ExactInputSingleParams({
                    tokenIn: assetIn,
                    tokenOut: dai, // DAI before conversion
                    fee: fee,
                    recipient: address(swapper), // to this contract for conversion
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            )
        );

        swapper.swap(assetIn, amountIn, usds, minAmountOut, recipient, abi.encode(fee));
    }
}

contract USDSToDAIUniswapV3Swapper_GetAmountOut_Test is USDSToDAIUniswapV3SwapperTest {
    function test_shouldCallQuoterQuoteExactInputSingle_withUSDSAssetIn() public {
        vm.expectCall(
            quoter,
            abi.encodeWithSelector(IUniswapQuoterLike.quoteExactInputSingle.selector, dai, assetOut, fee, amountIn, 0)
        );

        swapper.getAmountOut(usds, amountIn, assetOut, abi.encode(fee));
    }

    function test_shouldCallQuoterQuoteExactInputSingle_whenUSDSAssetOut() public {
        vm.expectCall(
            quoter,
            abi.encodeWithSelector(IUniswapQuoterLike.quoteExactInputSingle.selector, assetIn, dai, fee, amountIn, 0)
        );

        swapper.getAmountOut(assetIn, amountIn, usds, abi.encode(fee));
    }
}
