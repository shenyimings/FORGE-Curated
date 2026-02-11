// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { OneInchSwapper, IOneInchAggregationRouterLike, IERC20 } from "../../src/periphery/swapper/OneInchSwapper.sol";

abstract contract OneInchSwapperForkTest is Test {
    IOneInchAggregationRouterLike constant SWAP_ROUTER =
        IOneInchAggregationRouterLike(0x111111125421cA6dc452d289314280a0f8842A65);
    address constant EXECUTOR = 0x5141B82f5fFDa4c6fE1E372978F1C5427640a190;

    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    OneInchSwapper swapper;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public virtual {
        vm.createSelectFork("mainnet");

        swapper = new OneInchSwapper(owner, SWAP_ROUTER);

        vm.prank(owner);
        swapper.setAllowedExecutor(EXECUTOR, true);
    }
}

contract OneInchSwapper_Swap_ForkTest is OneInchSwapperForkTest {
    function _hexStringToBytes(string memory s) internal pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length >= 2 && ss[0] == "0" && ss[1] == "x", "Invalid hex prefix");
        uint256 len = (ss.length - 2) / 2;
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = _byteFromHexChar(ss[2 + i * 2]) << 4 | _byteFromHexChar(ss[3 + i * 2]);
        }
        return result;
    }

    function _byteFromHexChar(bytes1 c) internal pure returns (bytes1) {
        // forge-lint: disable-start(unsafe-typecast)
        if (c >= "0" && c <= "9") return bytes1(uint8(c) - uint8(bytes1("0")));
        if (c >= "a" && c <= "f") return bytes1(uint8(c) - uint8(bytes1("a")) + 10);
        if (c >= "A" && c <= "F") return bytes1(uint8(c) - uint8(bytes1("A")) + 10);
        revert("Invalid hex character");
        // forge-lint: disable-end(unsafe-typecast)
    }

    // needs to be run with --ffi flag
    function test_shouldSwapUSDCtoUSDT() public {
        vm.skip(!vm.envExists("ONE_INCH_API_KEY"));

        string[] memory inputs = new string[](10);
        inputs[0] = "curl";
        inputs[1] = "-X";
        inputs[2] = "GET";
        inputs[3] =
            "https://api.1inch.com/swap/v6.1/1/swap?src=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&dst=0xdAC17F958D2ee523a2206206994597C13D831ec7&amount=1000000000000&from=0x0000000000000000000000000000000000000000&origin=0x0000000000000000000000000000000000000000&slippage=1&disableEstimate=true";
        inputs[4] = "-H";
        inputs[5] = "accept: application/json";
        inputs[6] = "-H";
        inputs[7] = "content-type: application/json";
        inputs[8] = "-H";
        inputs[9] = "Authorization: Bearer ";
        inputs[9] = string.concat(inputs[9], vm.envString("ONE_INCH_API_KEY"));

        bytes memory routerTxData;
        // forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.ffi(inputs) returns (bytes memory res) {
            string memory json = string(res);
            string memory routerTxDataString = vm.parseJsonString(json, ".tx.data");
            routerTxData = _hexStringToBytes(routerTxDataString);
        } catch {
            vm.skip(true);
        }

        uint256 amountIn = 1_000_000e6; // need to update in API call too if changed
        uint256 minAmountOut = 995_000e6; // 0.5% slippage

        deal(address(USDC), user, amountIn);
        vm.prank(user);
        require(USDC.transfer(address(swapper), amountIn));

        uint256 balanceBefore = USDT.balanceOf(user);
        uint256 amountOut = swapper.swap(address(USDC), amountIn, address(USDT), minAmountOut, user, routerTxData);
        uint256 balanceAfter = USDT.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, amountOut);
        assertGe(amountOut, minAmountOut);
    }

    // needs to be run with --ffi flag
    function test_shouldSwapUSDStoUSDT() public {
        vm.skip(!vm.envExists("ONE_INCH_API_KEY"));

        string[] memory inputs = new string[](10);
        inputs[0] = "curl";
        inputs[1] = "-X";
        inputs[2] = "GET";
        inputs[3] =
            "https://api.1inch.com/swap/v6.1/1/swap?src=0xdC035D45d973E3EC169d2276DDab16f1e407384F&dst=0xdAC17F958D2ee523a2206206994597C13D831ec7&amount=1000000000000000000000000&from=0x0000000000000000000000000000000000000000&origin=0x0000000000000000000000000000000000000000&slippage=1&disableEstimate=true";
        inputs[4] = "-H";
        inputs[5] = "accept: application/json";
        inputs[6] = "-H";
        inputs[7] = "content-type: application/json";
        inputs[8] = "-H";
        inputs[9] = "Authorization: Bearer ";
        inputs[9] = string.concat(inputs[9], vm.envString("ONE_INCH_API_KEY"));

        bytes memory routerTxData;
        // forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.ffi(inputs) returns (bytes memory res) {
            string memory json = string(res);
            string memory routerTxDataString = vm.parseJsonString(json, ".tx.data");
            routerTxData = _hexStringToBytes(routerTxDataString);
        } catch {
            vm.skip(true);
        }

        uint256 amountIn = 1_000_000e18; // need to update in API call too if changed
        uint256 minAmountOut = 995_000e6; // 0.5% slippage

        deal(address(USDS), user, amountIn);
        vm.prank(user);
        require(USDS.transfer(address(swapper), amountIn));

        uint256 balanceBefore = USDT.balanceOf(user);
        uint256 amountOut = swapper.swap(address(USDS), amountIn, address(USDT), minAmountOut, user, routerTxData);
        uint256 balanceAfter = USDT.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, amountOut);
        assertGe(amountOut, minAmountOut);
    }
}
