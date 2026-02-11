// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IUniswapSwapRouter02} from "src/interfaces/periphery/IUniswapSwapRouter02.sol";

contract MockUniswapSwapRouter02 is Test {
    struct MockV3SingleHopSwap {
        address fromToken;
        address toToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
        bool isExecuted;
    }

    struct MockV3MultiHopSwap {
        bytes32 encodedPath;
        IERC20 fromToken;
        IERC20 toToken;
        uint256 fromAmount;
        uint256 toAmount;
        bool isExecuted;
    }

    MockV3SingleHopSwap[] public v3SingleHopSwaps;

    MockV3MultiHopSwap[] public v3MultiHopSwaps;

    function mockNextUniswapV3SingleHopSwap(MockV3SingleHopSwap memory swap) external {
        v3SingleHopSwaps.push(swap);
    }

    function mockNextUniswapV3MultiHopSwap(MockV3MultiHopSwap memory swap) external {
        v3MultiHopSwaps.push(swap);
    }

    function exactInputSingle(IUniswapSwapRouter02.ExactInputSingleParams memory params)
        external
        payable
        returns (uint256 amountOut)
    {
        for (uint256 i = 0; i < v3SingleHopSwaps.length; i++) {
            MockV3SingleHopSwap memory swap = v3SingleHopSwaps[i];
            if (
                !swap.isExecuted && swap.fromToken == params.tokenIn && swap.toToken == params.tokenOut
                    && swap.fee == params.fee && swap.sqrtPriceLimitX96 == params.sqrtPriceLimitX96
            ) {
                require(swap.toAmount >= params.amountOutMinimum, "MockUniswapSwapRouter02: INSUFFICIENT_OUTPUT_AMOUNT");

                _executeV3SingleHopSwap(swap, params.recipient, i);
                return swap.toAmount;
            }
        }

        revert("MockUniswapSwapRouter02: No mocked v3 swap set");
    }

    function exactInput(IUniswapSwapRouter02.ExactInputParams memory params)
        external
        payable
        returns (uint256 amountOut)
    {
        for (uint256 i = 0; i < v3MultiHopSwaps.length; i++) {
            MockV3MultiHopSwap memory swap = v3MultiHopSwaps[i];
            bytes32 encodedPath = keccak256(params.path);
            if (
                !swap.isExecuted && swap.encodedPath == encodedPath && swap.fromAmount == params.amountIn
                    && swap.toAmount == params.amountOutMinimum
            ) {
                require(swap.toAmount >= params.amountOutMinimum, "MockUniswapSwapRouter02: INSUFFICIENT_OUTPUT_AMOUNT");

                _executeV3MultiHopSwap(swap, params.recipient, i);
                return swap.toAmount;
            }
        }

        revert("MockUniswapSwapRouter02: No mocked v3 swap set");
    }

    function exactOutputSingle(IUniswapSwapRouter02.ExactOutputSingleParams memory params)
        external
        payable
        returns (uint256 amountIn)
    {
        for (uint256 i = 0; i < v3SingleHopSwaps.length; i++) {
            MockV3SingleHopSwap memory swap = v3SingleHopSwaps[i];
            if (
                !swap.isExecuted && swap.fromToken == params.tokenIn && swap.toToken == params.tokenOut
                    && swap.fee == params.fee && swap.sqrtPriceLimitX96 == params.sqrtPriceLimitX96
            ) {
                require(swap.fromAmount <= params.amountInMaximum, "MockUniswapSwapRouter02: INSUFFICIENT_INPUT_AMOUNT");

                _executeV3SingleHopSwap(swap, params.recipient, i);
                return swap.fromAmount;
            }
        }

        revert("MockUniswapSwapRouter02: No mocked swap set");
    }

    function exactOutput(IUniswapSwapRouter02.ExactOutputParams memory params)
        external
        payable
        returns (uint256 amountIn)
    {
        for (uint256 i = 0; i < v3MultiHopSwaps.length; i++) {
            MockV3MultiHopSwap memory swap = v3MultiHopSwaps[i];
            bytes32 encodedPath = keccak256(params.path);
            if (
                !swap.isExecuted && swap.encodedPath == encodedPath && swap.fromAmount == params.amountInMaximum
                    && swap.toAmount == params.amountOut
            ) {
                require(swap.fromAmount <= params.amountInMaximum, "MockUniswapSwapRouter02: INSUFFICIENT_INPUT_AMOUNT");

                _executeV3MultiHopSwap(swap, params.recipient, i);
                return swap.fromAmount;
            }
        }

        revert("MockUniswapSwapRouter02: No mocked swap set");
    }

    function _executeV3SingleHopSwap(MockV3SingleHopSwap memory swap, address recipient, uint256 v3SingleHopSwapIndex)
        internal
    {
        // Transfer in the fromToken
        IERC20(swap.fromToken).transferFrom(msg.sender, address(this), swap.fromAmount);

        // Transfer out the toToken
        deal(address(swap.toToken), address(this), swap.toAmount);
        IERC20(swap.toToken).transfer(recipient, swap.toAmount);

        v3SingleHopSwaps[v3SingleHopSwapIndex].isExecuted = true;
    }

    function _executeV3MultiHopSwap(MockV3MultiHopSwap memory swap, address recipient, uint256 v3MultiHopSwapIndex)
        internal
    {
        // Transfer in the fromToken
        IERC20(swap.fromToken).transferFrom(msg.sender, address(this), swap.fromAmount);

        // Transfer out the toToken
        deal(address(swap.toToken), address(this), swap.toAmount);
        IERC20(swap.toToken).transfer(recipient, swap.toAmount);

        v3MultiHopSwaps[v3MultiHopSwapIndex].isExecuted = true;
    }
}
