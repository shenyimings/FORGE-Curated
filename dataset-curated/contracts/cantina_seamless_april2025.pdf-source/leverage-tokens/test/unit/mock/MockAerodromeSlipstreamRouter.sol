// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IAerodromeSlipstreamRouter} from "src/interfaces/periphery/IAerodromeSlipstreamRouter.sol";

contract MockAerodromeSlipstreamRouter is Test {
    struct MockSwapSingleHop {
        address fromToken;
        address toToken;
        uint256 fromAmount;
        uint256 toAmount;
        int24 tickSpacing;
        uint160 sqrtPriceLimitX96;
        bool isExecuted;
    }

    struct MockSwapMultiHop {
        bytes32 encodedPath;
        IERC20 fromToken;
        IERC20 toToken;
        uint256 fromAmount;
        uint256 toAmount;
        bool isExecuted;
    }

    MockSwapSingleHop[] public singleHopSwaps;

    MockSwapMultiHop[] public multiHopSwaps;

    function mockNextSingleHopSwap(MockSwapSingleHop memory swap) public {
        singleHopSwaps.push(swap);
    }

    function mockNextMultiHopSwap(MockSwapMultiHop memory swap) public {
        multiHopSwaps.push(swap);
    }

    function exactInputSingle(IAerodromeSlipstreamRouter.ExactInputSingleParams memory params)
        external
        payable
        returns (uint256 amountOut)
    {
        for (uint256 i = 0; i < singleHopSwaps.length; i++) {
            MockSwapSingleHop memory swap = singleHopSwaps[i];
            if (
                !swap.isExecuted && swap.fromToken == params.tokenIn && swap.toToken == params.tokenOut
                    && swap.tickSpacing == params.tickSpacing && swap.sqrtPriceLimitX96 == params.sqrtPriceLimitX96
            ) {
                require(
                    swap.toAmount >= params.amountOutMinimum,
                    "MockAerodromeSlipstreamRouter: INSUFFICIENT_OUTPUT_AMOUNT"
                );

                _executeSingleHopSwap(swap, params.recipient, i);
                return swap.toAmount;
            }
        }

        revert("MockAerodromeSlipstreamRouter: No mocked swap set");
    }

    function exactInput(IAerodromeSlipstreamRouter.ExactInputParams memory params)
        external
        payable
        returns (uint256 amountOut)
    {
        for (uint256 i = 0; i < multiHopSwaps.length; i++) {
            MockSwapMultiHop memory swap = multiHopSwaps[i];
            bytes32 encodedPath = keccak256(params.path);
            if (
                !swap.isExecuted && swap.encodedPath == encodedPath && swap.fromAmount == params.amountIn
                    && swap.toAmount == params.amountOutMinimum
            ) {
                require(
                    swap.toAmount >= params.amountOutMinimum,
                    "MockAerodromeSlipstreamRouter: INSUFFICIENT_OUTPUT_AMOUNT"
                );

                _executeMultiHopSwap(swap, params.recipient, i);
                return swap.toAmount;
            }
        }

        revert("MockAerodromeSlipstreamRouter: No mocked swap set");
    }

    function exactOutputSingle(IAerodromeSlipstreamRouter.ExactOutputSingleParams memory params)
        external
        payable
        returns (uint256 amountIn)
    {
        for (uint256 i = 0; i < singleHopSwaps.length; i++) {
            MockSwapSingleHop memory swap = singleHopSwaps[i];
            if (
                !swap.isExecuted && swap.fromToken == params.tokenIn && swap.toToken == params.tokenOut
                    && swap.tickSpacing == params.tickSpacing && swap.sqrtPriceLimitX96 == params.sqrtPriceLimitX96
            ) {
                require(
                    swap.fromAmount <= params.amountInMaximum,
                    "MockAerodromeSlipstreamRouter: INSUFFICIENT_INPUT_AMOUNT"
                );

                _executeSingleHopSwap(swap, params.recipient, i);
                return swap.fromAmount;
            }
        }

        revert("MockAerodromeSlipstreamRouter: No mocked swap set");
    }

    function exactOutput(IAerodromeSlipstreamRouter.ExactOutputParams memory params)
        external
        payable
        returns (uint256 amountIn)
    {
        for (uint256 i = 0; i < multiHopSwaps.length; i++) {
            MockSwapMultiHop memory swap = multiHopSwaps[i];
            bytes32 encodedPath = keccak256(params.path);
            if (
                !swap.isExecuted && swap.encodedPath == encodedPath && swap.fromAmount == params.amountInMaximum
                    && swap.toAmount == params.amountOut
            ) {
                require(
                    swap.fromAmount <= params.amountInMaximum,
                    "MockAerodromeSlipstreamRouter: INSUFFICIENT_INPUT_AMOUNT"
                );

                _executeMultiHopSwap(swap, params.recipient, i);
                return swap.fromAmount;
            }
        }

        revert("MockAerodromeSlipstreamRouter: No mocked swap set");
    }

    function _executeSingleHopSwap(MockSwapSingleHop memory swap, address recipient, uint256 singleHopSwapIndex)
        internal
    {
        // Transfer in the fromToken
        IERC20(swap.fromToken).transferFrom(msg.sender, address(this), swap.fromAmount);

        // Transfer out the toToken
        deal(address(swap.toToken), address(this), swap.toAmount);
        IERC20(swap.toToken).transfer(recipient, swap.toAmount);

        singleHopSwaps[singleHopSwapIndex].isExecuted = true;
    }

    function _executeMultiHopSwap(MockSwapMultiHop memory swap, address recipient, uint256 multiHopSwapIndex)
        internal
    {
        // Transfer in the fromToken
        IERC20(swap.fromToken).transferFrom(msg.sender, address(this), swap.fromAmount);

        // Transfer out the toToken
        deal(address(swap.toToken), address(this), swap.toAmount);
        IERC20(swap.toToken).transfer(recipient, swap.toAmount);

        multiHopSwaps[multiHopSwapIndex].isExecuted = true;
    }
}
