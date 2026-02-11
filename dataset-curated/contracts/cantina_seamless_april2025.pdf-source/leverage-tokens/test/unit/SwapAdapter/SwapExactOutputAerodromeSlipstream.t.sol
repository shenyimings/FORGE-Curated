// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapterTest} from "./SwapAdapter.t.sol";
import {MockAerodromeSlipstreamRouter} from "test/unit/mock/MockAerodromeSlipstreamRouter.sol";
import {SwapPathLib} from "test/utils/SwapPathLib.sol";

//  Inherited in `SwapExactOutput.t.sol ` tests
abstract contract SwapExactOutputAerodromeSlipstreamTest is SwapAdapterTest {
    function test_SwapExactOutputAerodromeSlipstream_SingleHop() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputAerodromeSlipstream(path, tickSpacing, outputAmount, maxInputAmount, false);

        // `SwapAdapter._swapExactOutputAerodromeSlipstream` does not transfer in the fromToken,
        // `SwapAdapter.swapExactOutput` does which is the external function that calls
        // `_swapExactOutputAerodromeSlipstream`
        deal(address(fromToken), address(swapAdapter), maxInputAmount);

        uint256 inputAmount =
            swapAdapter.exposed_swapExactOutputAerodromeSlipstream(outputAmount, maxInputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeSlipstreamRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_SwapExactOutputAerodromeSlipstream_MultiHop() public {
        uint256 outputAmount = 5 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        int24[] memory tickSpacing = new int24[](2);
        tickSpacing[0] = 500;
        tickSpacing[1] = 300;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactOutputAerodromeSlipstream(path, tickSpacing, outputAmount, maxInputAmount, true);

        // `SwapAdapter._swapExactOutputAerodromeSlipstream` does not transfer in the fromToken,
        // `SwapAdapter.swapExactOutput` does which is the external function that calls
        // `_swapExactOutputAerodromeSlipstream`
        deal(address(fromToken), address(swapAdapter), maxInputAmount);

        uint256 inputAmount =
            swapAdapter.exposed_swapExactOutputAerodromeSlipstream(outputAmount, maxInputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeSlipstreamRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_SwapExactOutputAerodromeSlipstream_InvalidNumTicks() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME_SLIPSTREAM,
            path: path,
            encodedPath: SwapPathLib._encodeAerodromeSlipstreamPath(path, tickSpacing, true),
            fees: new uint24[](0),
            tickSpacing: tickSpacing,
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(0),
                aerodromePoolFactory: address(0),
                aerodromeSlipstreamRouter: address(mockAerodromeSlipstreamRouter),
                uniswapSwapRouter02: address(0),
                uniswapV2Router02: address(0)
            })
        });

        vm.expectRevert(ISwapAdapter.InvalidNumTicks.selector);
        swapAdapter.exposed_swapExactOutputAerodromeSlipstream(outputAmount, maxInputAmount, swapContext);
    }

    function _mock_SwapExactOutputAerodromeSlipstream(
        address[] memory path,
        int24[] memory tickSpacing,
        uint256 outputAmount,
        uint256 maxInputAmount,
        bool isMultiHop
    ) internal returns (ISwapAdapter.SwapContext memory swapContext) {
        swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME_SLIPSTREAM,
            path: path,
            encodedPath: SwapPathLib._encodeAerodromeSlipstreamPath(path, tickSpacing, true),
            fees: new uint24[](0),
            tickSpacing: tickSpacing,
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(0),
                aerodromePoolFactory: address(0),
                aerodromeSlipstreamRouter: address(mockAerodromeSlipstreamRouter),
                uniswapSwapRouter02: address(0),
                uniswapV2Router02: address(0)
            })
        });

        if (isMultiHop) {
            MockAerodromeSlipstreamRouter.MockSwapMultiHop memory mockSwap = MockAerodromeSlipstreamRouter
                .MockSwapMultiHop({
                encodedPath: keccak256(SwapPathLib._encodeAerodromeSlipstreamPath(path, tickSpacing, true)),
                fromToken: IERC20(path[0]),
                toToken: IERC20(path[path.length - 1]),
                fromAmount: maxInputAmount,
                toAmount: outputAmount,
                isExecuted: false
            });
            mockAerodromeSlipstreamRouter.mockNextMultiHopSwap(mockSwap);
        } else {
            MockAerodromeSlipstreamRouter.MockSwapSingleHop memory mockSwap = MockAerodromeSlipstreamRouter
                .MockSwapSingleHop({
                fromToken: path[0],
                toToken: path[path.length - 1],
                fromAmount: maxInputAmount,
                toAmount: outputAmount,
                tickSpacing: tickSpacing[0],
                sqrtPriceLimitX96: 0,
                isExecuted: false
            });
            mockAerodromeSlipstreamRouter.mockNextSingleHopSwap(mockSwap);
        }

        return swapContext;
    }
}
