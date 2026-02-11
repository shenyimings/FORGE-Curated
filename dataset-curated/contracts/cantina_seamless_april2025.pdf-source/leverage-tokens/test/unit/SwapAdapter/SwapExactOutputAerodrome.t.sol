// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IAerodromeRouter} from "src/interfaces/periphery/IAerodromeRouter.sol";
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapterTest} from "./SwapAdapter.t.sol";
import {MockAerodromeRouter} from "test/unit/mock/MockAerodromeRouter.sol";

//  Inherited in `SwapExactOutput.t.sol` tests
abstract contract SwapExactOutputAerodromeTest is SwapAdapterTest {
    address public aerodromePoolFactory = makeAddr("aerodromePoolFactory");

    function test_SwapExactOutputAerodrome_SingleHop() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactOutputAerodrome(path, outputAmount, maxInputAmount);

        // `SwapAdapter._swapExactOutputAerodrome` does not transfer in the fromToken,
        // `SwapAdapter.swapExactOutput` does which is the external function that calls
        // `_swapExactOutputAerodrome`
        deal(address(fromToken), address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.exposed_swapExactOutputAerodrome(outputAmount, maxInputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_SwapExactOutputAerodrome_MultiHop() public {
        uint256 outputAmount = 10 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactOutputAerodrome(path, outputAmount, maxInputAmount);

        // `SwapAdapter._swapExactOutputAerodrome` does not transfer in the fromToken,
        // `SwapAdapter.swapExactOutput` does which is the external function that calls
        // `_swapExactOutputAerodrome`
        deal(address(fromToken), address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.exposed_swapExactOutputAerodrome(outputAmount, maxInputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        assertEq(inputAmount, maxInputAmount);
    }

    function test_SwapExactOutputAerodrome_SurplusToToken() public {
        uint256 outputAmount = 10 ether;
        uint256 surplusOutputAmount = 1 ether;
        uint256 maxInputAmount = 100 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME,
            path: path,
            encodedPath: new bytes(0),
            fees: new uint24[](0),
            tickSpacing: new int24[](0),
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(mockAerodromeRouter),
                aerodromePoolFactory: aerodromePoolFactory,
                aerodromeSlipstreamRouter: address(0),
                uniswapSwapRouter02: address(0),
                uniswapV2Router02: address(0)
            })
        });

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route(address(fromToken), address(toToken), false, aerodromePoolFactory);
        MockAerodromeRouter.MockSwap memory mockSwap = MockAerodromeRouter.MockSwap({
            inputToken: fromToken,
            outputToken: toToken,
            inputAmount: maxInputAmount,
            outputAmount: outputAmount + surplusOutputAmount,
            encodedRoutes: keccak256(abi.encode(routes)),
            deadline: block.timestamp,
            isExecuted: false
        });
        mockAerodromeRouter.mockNextSwap(mockSwap);

        // Mock the additional expected swap of the surplus toToken
        routes[0] = IAerodromeRouter.Route(path[1], path[0], false, aerodromePoolFactory);
        MockAerodromeRouter.MockSwap memory mockSwap2 = MockAerodromeRouter.MockSwap({
            inputToken: toToken,
            outputToken: fromToken,
            inputAmount: surplusOutputAmount,
            outputAmount: 0.5 ether,
            encodedRoutes: keccak256(abi.encode(routes)),
            deadline: block.timestamp,
            isExecuted: false
        });
        mockAerodromeRouter.mockNextSwap(mockSwap2);

        // `SwapAdapter._swapExactOutputAerodrome` does not transfer in the fromToken,
        // `SwapAdapter.swapExactOutput` does which is the external function that calls
        // `_swapExactOutputAerodrome`
        deal(address(fromToken), address(swapAdapter), maxInputAmount);

        uint256 inputAmount = swapAdapter.exposed_swapExactOutputAerodrome(outputAmount, maxInputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeRouter)), maxInputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), outputAmount);
        // The inputAmount should be less than the maxInputAmount by the surplus received from the second swap
        assertEq(inputAmount, maxInputAmount - mockSwap2.outputAmount);
    }

    function _mock_SwapExactOutputAerodrome(address[] memory path, uint256 outputAmount, uint256 maxInputAmount)
        internal
        returns (ISwapAdapter.SwapContext memory swapContext)
    {
        swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME,
            path: path,
            encodedPath: new bytes(0),
            fees: new uint24[](0),
            tickSpacing: new int24[](0),
            exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                aerodromeRouter: address(mockAerodromeRouter),
                aerodromePoolFactory: aerodromePoolFactory,
                aerodromeSlipstreamRouter: address(0),
                uniswapSwapRouter02: address(0),
                uniswapV2Router02: address(0)
            })
        });

        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](path.length - 1);
        for (uint256 i = 0; i < path.length - 1; i++) {
            routes[i] = IAerodromeRouter.Route(path[i], path[i + 1], false, aerodromePoolFactory);
        }

        MockAerodromeRouter.MockSwap memory mockSwap = MockAerodromeRouter.MockSwap({
            inputToken: IERC20(path[0]),
            outputToken: IERC20(path[path.length - 1]),
            inputAmount: maxInputAmount,
            outputAmount: outputAmount,
            encodedRoutes: keccak256(abi.encode(routes)),
            deadline: block.timestamp,
            isExecuted: false
        });
        mockAerodromeRouter.mockNextSwap(mockSwap);

        return swapContext;
    }
}
