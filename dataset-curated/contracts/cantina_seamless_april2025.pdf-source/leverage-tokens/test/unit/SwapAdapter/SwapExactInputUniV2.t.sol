// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapterTest} from "./SwapAdapter.t.sol";
import {MockUniswapV2Router02} from "test/unit/mock/MockUniswapV2Router02.sol";

//  Inherited in `SwapExactInput.t.sol` tests
abstract contract SwapExactInputUniV2Test is SwapAdapterTest {
    function test_SwapExactInputUniV2_SingleHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactInputUniV2(path, inputAmount, minOutputAmount);

        // `SwapAdapter._swapExactInputUniV2` does not transfer in the fromToken,
        // `SwapAdapterHarness.swapExactInput` does which is the external function that calls
        // `_swapExactInputUniV2`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.exposed_swapExactInputUniV2(inputAmount, minOutputAmount, swapContext);

        // Uniswap receives the fromToken
        assertEq(fromToken.balanceOf(address(mockUniswapV2Router02)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_SwapExactInputUniV2_MultiHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactInputUniV2(path, inputAmount, minOutputAmount);

        // `SwapAdapter._swapExactInputUniV2` does not transfer in the fromToken,
        // `SwapAdapterHarness.swapExactInput` does which is the external function that calls
        // `_swapExactInputUniV2`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.exposed_swapExactInputUniV2(inputAmount, minOutputAmount, swapContext);

        // Uniswap receives the fromToken
        assertEq(fromToken.balanceOf(address(mockUniswapV2Router02)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function _mock_SwapExactInputUniV2(address[] memory path, uint256 inputAmount, uint256 minOutputAmount)
        internal
        returns (ISwapAdapter.SwapContext memory swapContext)
    {
        swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.UNISWAP_V2,
            path: path,
            encodedPath: new bytes(0),
            fees: new uint24[](0),
            tickSpacing: new int24[](0),
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(0),
                aerodromePoolFactory: address(0),
                aerodromeSlipstreamRouter: address(0),
                uniswapSwapRouter02: address(0),
                uniswapV2Router02: address(mockUniswapV2Router02)
            })
        });

        MockUniswapV2Router02.MockV2Swap memory mockSwap = MockUniswapV2Router02.MockV2Swap({
            fromToken: IERC20(path[0]),
            toToken: IERC20(path[path.length - 1]),
            fromAmount: inputAmount,
            toAmount: minOutputAmount,
            encodedPath: keccak256(abi.encode(path)),
            isExecuted: false
        });
        mockUniswapV2Router02.mockNextUniswapV2Swap(mockSwap);

        return swapContext;
    }
}
