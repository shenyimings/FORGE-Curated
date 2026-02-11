// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IAerodromeRouter} from "src/interfaces/periphery/IAerodromeRouter.sol";
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapterTest} from "./SwapAdapter.t.sol";
import {MockAerodromeRouter} from "test/unit/mock/MockAerodromeRouter.sol";

//  Inherited in `SwapExactInput.t.sol` tests
abstract contract SwapExactInputAerodromeTest is SwapAdapterTest {
    address public aerodromePoolFactory = makeAddr("aerodromePoolFactory");

    function test_SwapExactInputAerodrome_SingleHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactInputAerodrome(path, inputAmount, minOutputAmount);

        // `SwapAdapter._swapExactInputAerodrome` does not transfer in the inputToken,
        // `SwapAdapter.swapExactInput` does which is the external function that calls
        // `_swapExactInputAerodrome`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.exposed_swapExactInputAerodrome(inputAmount, minOutputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function test_SwapExactInputAerodrome_MultiHop() public {
        uint256 inputAmount = 100 ether;
        uint256 minOutputAmount = 10 ether;

        address[] memory path = new address[](3);
        path[0] = address(fromToken);
        path[1] = makeAddr("additional hop");
        path[2] = address(toToken);

        ISwapAdapter.SwapContext memory swapContext = _mock_SwapExactInputAerodrome(path, inputAmount, minOutputAmount);

        // `SwapAdapter._swapExactInputAerodrome` does not transfer in the inputToken,
        // `SwapAdapter.swapExactInput` does which is the external function that calls
        // `_swapExactInputAerodrome`
        deal(address(fromToken), address(swapAdapter), inputAmount);

        uint256 outputAmount = swapAdapter.exposed_swapExactInputAerodrome(inputAmount, minOutputAmount, swapContext);

        // Aerodrome receives the fromToken
        assertEq(fromToken.balanceOf(address(mockAerodromeRouter)), inputAmount);
        // We receive the toToken
        assertEq(toToken.balanceOf(address(this)), minOutputAmount);
        assertEq(outputAmount, minOutputAmount);
    }

    function _mock_SwapExactInputAerodrome(address[] memory path, uint256 inputAmount, uint256 minOutputAmount)
        internal
        returns (ISwapAdapter.SwapContext memory swapContext)
    {
        swapContext = ISwapAdapter.SwapContext({
            exchange: ISwapAdapter.Exchange.AERODROME,
            encodedPath: new bytes(0),
            path: path,
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
            inputAmount: inputAmount,
            outputAmount: minOutputAmount,
            encodedRoutes: keccak256(abi.encode(routes)),
            deadline: block.timestamp,
            isExecuted: false
        });
        mockAerodromeRouter.mockNextSwap(mockSwap);

        return swapContext;
    }
}
