// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapterTest} from "./SwapAdapter.t.sol";
import {MockUniswapSwapRouter02} from "test/unit/mock/MockUniswapSwapRouter02.sol";
import {SwapPathLib} from "test/utils/SwapPathLib.sol";

//  Inherited in `SwapExactInput.t.sol` tests
abstract contract SwapExactInputUniV3Test is SwapAdapterTest {
    function test_SwapExactInputUniV3_SingleHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactInputUniV3(path, fees, inputAmount, minOutputAmount, false);

        // `SwapAdapter._swapExactInputUniV3` does not transfer in the inputToken,
        // `SwapAdapter.swapExactInput` does which is the external function that calls
        // `_swapExactInputUniV3`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.exposed_swapExactInputUniV3(inputAmount, minOutputAmount, swapContext);

        // Uniswap receives the fromToken
        assertEq(fromToken.balanceOf(address(mockUniswapSwapRouter02)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_SwapExactInputUniV3_MultiHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        uint24[] memory fees = new uint24[](2);
        fees[0] = 500;
        fees[1] = 300;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactInputUniV3(path, fees, inputAmount, minOutputAmount, true);

        // `SwapAdapter._swapExactInputUniV3` does not transfer in the fromToken,
        // `SwapAdapterHarness.swapExactInput` does which is the external function that calls
        // `_swapExactInputUniV3`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.exposed_swapExactInputUniV3(inputAmount, minOutputAmount, swapContext);

        // Uniswap receives the fromToken
        assertEq(fromToken.balanceOf(address(mockUniswapSwapRouter02)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_SwapExactInputUniV3_InvalidNumFees() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        ISwapAdapter.SwapContext memory swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.UNISWAP_V3,
            path: path,
            encodedPath: SwapPathLib._encodeUniswapV3Path(path, fees, false),
            fees: fees,
            tickSpacing: new int24[](0),
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(0),
                aerodromePoolFactory: address(0),
                aerodromeSlipstreamRouter: address(0),
                uniswapSwapRouter02: address(mockUniswapSwapRouter02),
                uniswapV2Router02: address(0)
            })
        });

        vm.expectRevert(ISwapAdapter.InvalidNumFees.selector);
        swapAdapter.exposed_swapExactInputUniV3(inputAmount, minOutputAmount, swapContext);
    }

    function _mock_SwapExactInputUniV3(
        address[] memory path,
        uint24[] memory fees,
        uint256 inputAmount,
        uint256 minOutputAmount,
        bool isMultiHop
    ) internal returns (ISwapAdapter.SwapContext memory swapContext) {
        swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.UNISWAP_V3,
            path: path,
            encodedPath: SwapPathLib._encodeUniswapV3Path(path, fees, false),
            fees: fees,
            tickSpacing: new int24[](0),
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(0),
                aerodromePoolFactory: address(0),
                aerodromeSlipstreamRouter: address(0),
                uniswapSwapRouter02: address(mockUniswapSwapRouter02),
                uniswapV2Router02: address(0)
            })
        });

        if (isMultiHop) {
            MockUniswapSwapRouter02.MockV3MultiHopSwap memory mockSwap = MockUniswapSwapRouter02.MockV3MultiHopSwap({
                encodedPath: keccak256(SwapPathLib._encodeUniswapV3Path(path, fees, false)),
                fromToken: IERC20(path[0]),
                toToken: IERC20(path[path.length - 1]),
                fromAmount: inputAmount,
                toAmount: minOutputAmount,
                isExecuted: false
            });
            mockUniswapSwapRouter02.mockNextUniswapV3MultiHopSwap(mockSwap);
        } else {
            MockUniswapSwapRouter02.MockV3SingleHopSwap memory mockSwap = MockUniswapSwapRouter02.MockV3SingleHopSwap({
                fromToken: path[0],
                toToken: path[path.length - 1],
                fromAmount: inputAmount,
                toAmount: minOutputAmount,
                fee: fees[0],
                sqrtPriceLimitX96: 0,
                isExecuted: false
            });
            mockUniswapSwapRouter02.mockNextUniswapV3SingleHopSwap(mockSwap);
        }

        return swapContext;
    }
}
