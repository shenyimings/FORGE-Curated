// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapExactOutputAerodromeTest} from "./SwapExactOutputAerodrome.t.sol";
import {SwapExactOutputAerodromeSlipstreamTest} from "./SwapExactOutputAerodromeSlipstream.t.sol";
import {SwapExactOutputUniV2Test} from "./SwapExactOutputUniV2.t.sol";
import {SwapExactOutputUniV3Test} from "./SwapExactOutputUniV3.t.sol";

contract SwapExactOutputTest is
    SwapExactOutputAerodromeTest,
    SwapExactOutputAerodromeSlipstreamTest,
    SwapExactOutputUniV2Test,
    SwapExactOutputUniV3Test
{
    function test_swapExactOutput_Aerodrome() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactOutputAerodrome(path, outputAmount, maxInputAmount);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_swapExactOutput_AerodromeSlipstream() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputAerodromeSlipstream(path, tickSpacing, outputAmount, maxInputAmount, false);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_swapExactOutput_UniV2() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactOutputUniV2(path, outputAmount, maxInputAmount);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_swapExactOutput_UniV3() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputUniV3(path, fees, outputAmount, maxInputAmount, false);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_swapExactOutput_UniV2_SenderReceivesExcessInputToken() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;
        uint256 excessInputAmount = 1;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputUniV2(path, outputAmount, maxInputAmount - excessInputAmount);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), excessInputAmount);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount - excessInputAmount);
    }

    function test_swapExactOutput_UniV3_SenderReceivesExcessInputToken() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;
        uint256 excessInputAmount = 1;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputUniV3(path, fees, outputAmount, maxInputAmount - excessInputAmount, false);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), excessInputAmount);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount - excessInputAmount);
    }

    function test_swapExactOutput_Aerodrome_SenderReceivesExcessInputToken() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;
        uint256 excessOutputAmount = 1;
        uint256 excessInputAmount = 1;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputAerodrome(path, outputAmount + excessOutputAmount, maxInputAmount);

        // Mock the additional expected swap of the surplus toToken from the first swap
        address[] memory path2 = new address[](2);
        path2[0] = address(toToken);
        path2[1] = address(fromToken);
        _mock_SwapExactOutputAerodrome(path2, excessInputAmount, excessOutputAmount);

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), excessInputAmount);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount - excessInputAmount);
    }

    function test_swapExactOutput_AerodromeSlipstream_SenderReceivesExcessInputToken() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;
        uint256 excessInputAmount = 1;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactOutputAerodromeSlipstream(
            path, tickSpacing, outputAmount, maxInputAmount - excessInputAmount, false
        );

        deal(address(fromToken), address(this), maxInputAmount);
        fromToken.approve(address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.swapExactOutput(fromToken, outputAmount, maxInputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), excessInputAmount);
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount - excessInputAmount);
    }
}
