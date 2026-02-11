// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IAerodromeRouter} from "src/interfaces/periphery/IAerodromeRouter.sol";

contract MockAerodromeRouter is Test {
    struct MockSwap {
        IERC20 inputToken;
        IERC20 outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        bytes32 encodedRoutes;
        uint256 deadline;
        bool isExecuted;
    }

    MockSwap[] public swaps;

    function mockNextSwap(MockSwap memory swap) external {
        swaps.push(swap);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        IAerodromeRouter.Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        for (uint256 i = 0; i < swaps.length; i++) {
            MockSwap memory swap = swaps[i];
            bytes32 encodedRoute = keccak256(abi.encode(routes));
            if (!swap.isExecuted && swap.encodedRoutes == encodedRoute && swap.deadline == deadline) {
                require(swap.outputAmount >= amountOutMin, "MockAerodromeRouter: INSUFFICIENT_OUTPUT_AMOUNT");

                // Transfer in the inputToken
                swap.inputToken.transferFrom(msg.sender, address(this), swap.inputAmount);

                // Transfer out the outputToken
                deal(
                    address(swap.outputToken),
                    address(this),
                    swap.outputToken.balanceOf(address(this)) + swap.outputAmount
                );
                swap.outputToken.transfer(to, swap.outputAmount);

                swaps[i].isExecuted = true;

                uint256[] memory returnAmounts = new uint256[](2);
                returnAmounts[0] = amountIn;
                returnAmounts[1] = swap.outputAmount;
                return returnAmounts;
            }
        }

        revert("MockAerodromeRouter: No mocked swap set");
    }
}
