// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapExactInputAerodromeTest} from "./SwapExactInputAerodrome.t.sol";
import {SwapExactInputAerodromeSlipstreamTest} from "./SwapExactInputAerodromeSlipstream.t.sol";
import {SwapExactInputUniV2Test} from "./SwapExactInputUniV2.t.sol";
import {SwapExactInputUniV3Test} from "./SwapExactInputUniV3.t.sol";

contract SwapExactFromToMinToTest is
    SwapExactInputAerodromeTest,
    SwapExactInputAerodromeSlipstreamTest,
    SwapExactInputUniV2Test,
    SwapExactInputUniV3Test
{
    function test_swapExactInput_Aerodrome() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactInputAerodrome(path, inputAmount, minOutputAmount);

        deal(address(fromToken), address(this), inputAmount);
        fromToken.approve(address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.swapExactInput(fromToken, inputAmount, minOutputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_swapExactInput_AerodromeSlipstream() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactInputAerodromeSlipstream(path, tickSpacing, inputAmount, minOutputAmount, false);

        deal(address(fromToken), address(this), inputAmount);
        fromToken.approve(address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.swapExactInput(fromToken, inputAmount, minOutputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_swapExactInput_UniV2() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactInputUniV2(path, inputAmount, minOutputAmount);

        deal(address(fromToken), address(this), inputAmount);
        fromToken.approve(address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.swapExactInput(fromToken, inputAmount, minOutputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_swapExactFromToMinTo_UniV3() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactInputUniV3(path, fees, inputAmount, minOutputAmount, false);

        deal(address(fromToken), address(this), inputAmount);
        fromToken.approve(address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.swapExactInput(fromToken, inputAmount, minOutputAmount, swapContext);

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }
}
