// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import {
    OneInchSwapper,
    IOneInchAggregationRouterLike,
    IERC20,
    ISwapper
} from "../../../../src/periphery/swapper/OneInchSwapper.sol";

abstract contract OneInchSwapperTest is Test {
    OneInchSwapper swapper;

    address owner = makeAddr("owner");
    address router = makeAddr("router");
    address assetIn = makeAddr("assetIn");
    address assetOut = makeAddr("assetOut");
    uint256 amountIn = 1e18;
    uint256 minAmountOut = 1e18;
    uint256 amountOut = 1e18;
    uint256 flags = 5;
    bytes swapData = hex"1234";
    address recipient = makeAddr("recipient");
    address executor = makeAddr("executor");
    IOneInchAggregationRouterLike.SwapDescription desc;
    bytes swapperParams;

    function _encodeSwapperParams() internal view returns (bytes memory) {
        return abi.encodeWithSignature("randomSig()", executor, desc, swapData);
    }

    function setUp() public virtual {
        swapper = new OneInchSwapper(owner, IOneInchAggregationRouterLike(router));

        vm.mockCall(assetIn, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(
            router, abi.encodeWithSelector(IOneInchAggregationRouterLike.swap.selector), abi.encode(amountOut, amountIn)
        );

        desc = IOneInchAggregationRouterLike.SwapDescription({
            srcToken: assetIn,
            dstToken: assetOut,
            srcReceiver: payable(executor),
            dstReceiver: payable(address(0)), // will be overwritten in swap()
            amount: amountIn,
            minReturnAmount: minAmountOut,
            flags: flags
        });
        swapperParams = _encodeSwapperParams();
    }
}

contract OneInchSwapper_Swap_Test is OneInchSwapperTest {
    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        swapper.setAllowedExecutor(executor, true);
    }

    function test_shouldRevert_whenAssetInIsZeroAddress() public {
        vm.expectRevert(OneInchSwapper.ZeroAddress.selector);
        swapper.swap(address(0), amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenAssetOutIsZeroAddress() public {
        vm.expectRevert(OneInchSwapper.ZeroAddress.selector);
        swapper.swap(assetIn, amountIn, address(0), minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenAssetInEqualsAssetOut() public {
        vm.expectRevert(OneInchSwapper.IdenticalAddresses.selector);
        swapper.swap(assetIn, amountIn, assetIn, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenAmountInIsZero() public {
        vm.expectRevert(OneInchSwapper.InsufficientInputAmount.selector);
        swapper.swap(assetIn, 0, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenMinAmountOutIsZero() public {
        vm.expectRevert(OneInchSwapper.InsufficientOutputAmount.selector);
        swapper.swap(assetIn, amountIn, assetOut, 0, recipient, swapperParams);
    }

    function test_shouldRevert_whenExecutorIsNotAllowed() public {
        executor = makeAddr("notAllowedExecutor");
        swapperParams = _encodeSwapperParams();

        vm.expectRevert(OneInchSwapper.UnauthorizedExecutor.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenSrcTokenDoesNotMatchAssetIn() public {
        desc.srcToken = makeAddr("differentAssetIn");
        swapperParams = _encodeSwapperParams();

        vm.expectRevert(OneInchSwapper.InvalidSwapDescription.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenDstTokenDoesNotMatchAssetOut() public {
        desc.dstToken = makeAddr("differentAssetOut");
        swapperParams = _encodeSwapperParams();

        vm.expectRevert(OneInchSwapper.InvalidSwapDescription.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenAmountInDoesNotMatchDescAmount() public {
        desc.amount = amountIn + 1;
        swapperParams = _encodeSwapperParams();

        vm.expectRevert(OneInchSwapper.InvalidSwapDescription.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldApproveRouter() public {
        vm.expectCall(assetIn, abi.encodeWithSelector(IERC20.approve.selector, router, amountIn));

        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldCallRouterSwap() public {
        vm.expectCall(
            router,
            abi.encodeWithSelector(
                IOneInchAggregationRouterLike.swap.selector,
                executor,
                IOneInchAggregationRouterLike.SwapDescription({
                    srcToken: assetIn,
                    dstToken: assetOut,
                    srcReceiver: payable(executor),
                    dstReceiver: payable(recipient),
                    amount: amountIn,
                    minReturnAmount: minAmountOut,
                    flags: flags
                }),
                swapData
            )
        );

        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenAmountOutIsLessThanMinAmountOut() public {
        vm.mockCall(
            router,
            abi.encodeWithSelector(IOneInchAggregationRouterLike.swap.selector),
            abi.encode(minAmountOut - 1, amountIn)
        );

        vm.expectRevert(OneInchSwapper.InsufficientOutputAmount.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldRevert_whenAmountInNotEqualToSpentAmount() public {
        vm.mockCall(
            router,
            abi.encodeWithSelector(IOneInchAggregationRouterLike.swap.selector),
            abi.encode(amountOut, amountIn - 1)
        );

        vm.expectRevert(OneInchSwapper.PartialFill.selector);
        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldEmit_Swap() public {
        vm.expectEmit();
        emit ISwapper.Swap(assetIn, assetOut, amountIn, amountOut);

        swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
    }

    function test_shouldReturnAmountOut() public {
        uint256 result = swapper.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
        assertEq(result, amountOut);
    }
}

contract OneInchSwapper_SetAllowedExecutor_Test is OneInchSwapperTest {
    function test_shouldRevert_whenNotOwner() public {
        vm.expectRevert();
        vm.prank(makeAddr("notOwner"));
        swapper.setAllowedExecutor(executor, true);
    }

    function test_shouldRevert_whenExecutorIsZeroAddress() public {
        vm.expectRevert(OneInchSwapper.ZeroAddress.selector);
        vm.prank(owner);
        swapper.setAllowedExecutor(address(0), true);
    }

    function test_shouldSetAllowedExecutor() public {
        vm.prank(owner);
        swapper.setAllowedExecutor(executor, true);
        assertTrue(swapper.allowedExecutors(executor));

        vm.prank(owner);
        swapper.setAllowedExecutor(executor, false);
        assertFalse(swapper.allowedExecutors(executor));
    }

    function test_shouldEmit_ExecutorAuthorizationUpdated() public {
        vm.expectEmit();
        emit OneInchSwapper.ExecutorAuthorizationUpdated(executor, true);

        vm.prank(owner);
        swapper.setAllowedExecutor(executor, true);

        vm.expectEmit();
        emit OneInchSwapper.ExecutorAuthorizationUpdated(executor, false);

        vm.prank(owner);
        swapper.setAllowedExecutor(executor, false);
    }
}
