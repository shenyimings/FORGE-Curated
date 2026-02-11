// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { UniswapV3SwapAdapter } from "../../src/swap/UniswapV3SwapAdapter.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract UniswapV3SwapAdapterIntegrationTest is BaseIntegrationTest {
    using SafeERC20 for IERC20;

    // Holds USDC, USDT and wM
    address constant USER = 0x77BAB32F75996de8075eBA62aEa7b1205cf7E004;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_757_587);
        super.setUp();
    }

    function test_initialState() external {
        assertEq(swapAdapter.swapRouter(), UNISWAP_V3_ROUTER);
        assertEq(swapAdapter.baseToken(), WRAPPED_M);
        assertTrue(swapAdapter.whitelistedTokens(WRAPPED_M));
        assertTrue(swapAdapter.whitelistedTokens(USDC));
        assertTrue(swapAdapter.whitelistedTokens(USDT));
    }

    function test_swapIn_USDC_to_WrappedM() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 997_000;

        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(USER);
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(USDC).approve(address(swapAdapter), amountIn);

        vm.startPrank(USER);
        uint256 amountOut = swapAdapter.swapIn(USDC, amountIn, minAmountOut, USER, "");

        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(USER);
        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(amountOut, amountIn, 1000);
        assertEq(usdcBalanceAfter, usdcBalanceBefore - amountIn);
        assertEq(wrappedMBalanceAfter, wrappedMBalanceBefore + amountOut);
    }

    function test_swapOut_wrappedM_to_USDC() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 997_000;

        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(USER);
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(WRAPPED_M).approve(address(swapAdapter), amountIn);

        vm.startPrank(USER);
        uint256 amountOut = swapAdapter.swapOut(USDC, amountIn, minAmountOut, USER, "");

        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(USER);
        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(amountOut, amountIn, 1000);

        assertEq(wrappedMBalanceAfter, wrappedMBalanceBefore - amountIn);
        assertEq(usdcBalanceAfter, usdcBalanceBefore + amountOut);
    }

    function test_swapIn_USDT_to_WrappedM() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 997_000;
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(USER);
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        // Encode path for USDT -> USDC -> Wrapped M
        bytes memory path = abi.encodePacked(
            USDT,
            uint24(100), // 0.01% fee
            USDC,
            uint24(100), // 0.01% fee
            WRAPPED_M
        );

        vm.prank(USER);
        IERC20(USDT).forceApprove(address(swapAdapter), amountIn);

        vm.startPrank(USER);
        uint256 amountOut = swapAdapter.swapIn(USDT, amountIn, minAmountOut, USER, path);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(USER);
        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(amountOut, amountIn, 1000);
        assertEq(usdtBalanceAfter, usdtBalanceBefore - amountIn);
        assertEq(wrappedMBalanceAfter, wrappedMBalanceBefore + amountOut);
    }

    function test_swapOut_wrappedM_to_USDT() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 997_000;

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(USER);
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        // Encode path for USDT -> USDC -> Wrapped M
        bytes memory path = abi.encodePacked(
            WRAPPED_M,
            uint24(100), // 0.01% fee
            USDC,
            uint24(100), // 0.01% fee
            USDT
        );

        vm.startPrank(USER);
        IERC20(WRAPPED_M).approve(address(swapAdapter), amountIn);

        vm.startPrank(USER);
        uint256 amountOut = swapAdapter.swapOut(USDT, amountIn, minAmountOut, USER, path);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(USER);
        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(amountOut, amountIn, 1000);
        assertEq(wrappedMBalanceAfter, wrappedMBalanceBefore - amountIn);
        assertEq(usdtBalanceAfter, usdtBalanceBefore + amountOut);
    }
}
