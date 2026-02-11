// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapterTest} from "./SwapAdapter.t.sol";
import {MockAerodromeSlipstreamRouter} from "test/unit/mock/MockAerodromeSlipstreamRouter.sol";
import {SwapPathLib} from "test/utils/SwapPathLib.sol";

//  Inherited in `SwapExactInput.t.sol` tests
abstract contract SwapExactInputAerodromeSlipstreamTest is SwapAdapterTest {
    function test_SwapExactInputAerodromeSlipstream_SingleHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactInputAerodromeSlipstream(path, tickSpacing, inputAmount, minOutputAmount, false);

        // `SwapAdapter._swapExactInputAerodromeSlipstream` does not transfer in the fromToken,
        // `SwapAdapter.swapExactInput` does which is the external function that calls
        // `_swapExactInputAerodromeSlipstream`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount =
            swapAdapter.exposed_swapExactInputAerodromeSlipstream(inputAmount, minOutputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeSlipstreamRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_SwapExactInputAerodromeSlipstream_MultiHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        int24[] memory tickSpacing = new int24[](2);
        tickSpacing[0] = 500;
        tickSpacing[1] = 300;

        ISwapAdapter.SwapContext memory swapContext =
            _mock_SwapExactInputAerodromeSlipstream(path, tickSpacing, inputAmount, minOutputAmount, true);

        // `SwapAdapter._swapExactInputAerodromeSlipstream` does not transfer in the fromToken,
        // `SwapAdapter.swapExactInput` does which is the external function that calls
        // `_swapExactInputAerodromeSlipstream`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount =
            swapAdapter.exposed_swapExactInputAerodromeSlipstream(inputAmount, minOutputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeSlipstreamRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_SwapExactInputAerodromeSlipstream_InvalidNumTicks() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        int24[] memory tickSpacing = new int24[](1);
        tickSpacing[0] = 500;

        ISwapAdapter.SwapContext memory swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME_SLIPSTREAM,
            path: path,
            encodedPath: SwapPathLib._encodeAerodromeSlipstreamPath(path, tickSpacing, false),
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
        swapAdapter.exposed_swapExactInputAerodromeSlipstream(inputAmount, minOutputAmount, swapContext);
    }

    function _mock_SwapExactInputAerodromeSlipstream(
        address[] memory path,
        int24[] memory tickSpacing,
        uint256 inputAmount,
        uint256 minOutputAmount,
        bool isMultiHop
    ) internal returns (ISwapAdapter.SwapContext memory swapContext) {
        swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME_SLIPSTREAM,
            path: path,
            encodedPath: SwapPathLib._encodeAerodromeSlipstreamPath(path, tickSpacing, false),
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
                encodedPath: keccak256(SwapPathLib._encodeAerodromeSlipstreamPath(path, tickSpacing, false)),
                fromToken: IERC20(path[0]),
                toToken: IERC20(path[path.length - 1]),
                fromAmount: inputAmount,
                toAmount: minOutputAmount,
                isExecuted: false
            });
            mockAerodromeSlipstreamRouter.mockNextMultiHopSwap(mockSwap);
        } else {
            MockAerodromeSlipstreamRouter.MockSwapSingleHop memory mockSwap = MockAerodromeSlipstreamRouter
                .MockSwapSingleHop({
                fromToken: path[0],
                toToken: path[path.length - 1],
                fromAmount: inputAmount,
                toAmount: minOutputAmount,
                tickSpacing: tickSpacing[0],
                sqrtPriceLimitX96: 0,
                isExecuted: false
            });
            mockAerodromeSlipstreamRouter.mockNextSingleHopSwap(mockSwap);
        }

        return swapContext;
    }
}
