// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IUniswapV2Router02} from "src/interfaces/periphery/IUniswapV2Router02.sol";

contract MockUniswapV2Router02 is Test {
    struct MockV2Swap {
        IERC20 fromToken;
        IERC20 toToken;
        uint256 fromAmount;
        uint256 toAmount;
        bytes32 encodedPath;
        bool isExecuted;
    }

    MockV2Swap[] public v2Swaps;

    function mockNextUniswapV2Swap(MockV2Swap memory swap) external {
        v2Swaps.push(swap);
    }

    function swapExactTokensForTokens(
        uint256, /* amountIn */
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external payable returns (uint256[] memory amounts) {
        for (uint256 i = 0; i < v2Swaps.length; i++) {
            MockV2Swap memory swap = v2Swaps[i];
            bytes32 encodedPath = keccak256(abi.encode(path));
            if (!swap.isExecuted && swap.encodedPath == encodedPath) {
                require(swap.toAmount >= amountOutMin, "MockUniswapV2Router02: INSUFFICIENT_OUTPUT_AMOUNT");

                _executeV2Swap(swap, to, i);
                amounts = new uint256[](path.length);
                amounts[0] = swap.fromAmount;
                amounts[path.length - 1] = swap.toAmount;
                return amounts;
            }
        }

        revert("MockUniswapV2Router02: No mocked v2 swap set");
    }

    function swapTokensForExactTokens(
        uint256, /* amountOut */
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external payable returns (uint256[] memory amounts) {
        for (uint256 i = 0; i < v2Swaps.length; i++) {
            MockV2Swap memory swap = v2Swaps[i];
            bytes32 encodedPath = keccak256(abi.encode(path));
            if (!swap.isExecuted && swap.encodedPath == encodedPath) {
                require(swap.fromAmount <= amountInMax, "MockUniswapV2Router02: INSUFFICIENT_INPUT_AMOUNT");

                _executeV2Swap(swap, to, i);
                amounts = new uint256[](path.length);
                amounts[0] = swap.fromAmount;
                amounts[path.length - 1] = swap.toAmount;
                return amounts;
            }
        }

        revert("MockUniswapV2Router02: No mocked v2 swap set");
    }

    function _executeV2Swap(MockV2Swap memory swap, address recipient, uint256 v2SwapIndex) internal {
        // Transfer in the fromToken
        IERC20(swap.fromToken).transferFrom(msg.sender, address(this), swap.fromAmount);

        // Transfer out the toToken
        deal(address(swap.toToken), address(this), swap.toAmount);
        IERC20(swap.toToken).transfer(recipient, swap.toAmount);

        v2Swaps[v2SwapIndex].isExecuted = true;
    }
}
