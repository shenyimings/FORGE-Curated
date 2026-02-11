// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";

contract MockSwapper is Test {
    struct MockedExactInputSwap {
        IERC20 toToken;
        uint256 toAmount;
        bool isExecuted;
    }

    struct MockedExactOutputSwap {
        IERC20 toToken;
        uint256 fromAmount;
        bool isExecuted;
    }

    mapping(IERC20 fromToken => MockedExactInputSwap[]) public nextExactInputSwap;
    mapping(IERC20 fromToken => MockedExactOutputSwap[]) public nextExactOutputSwap;

    function mockNextExactInputSwap(IERC20 fromToken, IERC20 toToken, uint256 mockedToAmount) external {
        nextExactInputSwap[fromToken].push(
            MockedExactInputSwap({toToken: toToken, toAmount: mockedToAmount, isExecuted: false})
        );
    }

    function mockNextExactOutputSwap(IERC20 fromToken, IERC20 toToken, uint256 mockedFromAmount) external {
        nextExactOutputSwap[fromToken].push(
            MockedExactOutputSwap({toToken: toToken, fromAmount: mockedFromAmount, isExecuted: false})
        );
    }

    function swapExactInput(
        IERC20 fromToken,
        uint256 inputAmount,
        uint256, /* minOutputAmount */
        ISwapAdapter.SwapContext memory /* swapContext */
    ) external returns (uint256) {
        SafeERC20.safeTransferFrom(fromToken, msg.sender, address(this), inputAmount);

        MockedExactInputSwap[] storage mockedSwaps = nextExactInputSwap[fromToken];
        for (uint256 i = 0; i < mockedSwaps.length; i++) {
            MockedExactInputSwap memory mockedSwap = mockedSwaps[i];

            if (!mockedSwap.isExecuted) {
                // Deal the toToken to the sender
                deal(
                    address(mockedSwap.toToken),
                    msg.sender,
                    mockedSwap.toToken.balanceOf(msg.sender) + mockedSwap.toAmount
                );

                // Set the swap as executed
                mockedSwaps[i].isExecuted = true;

                return mockedSwap.toAmount;
            }
        }

        // If no mocked swap is set, revert by default
        revert("MockSwapper: No mocked exact input swap set");
    }

    function swapExactOutput(
        IERC20 fromToken,
        uint256 outputAmount,
        uint256, /* maxInputAmount */
        ISwapAdapter.SwapContext memory /* swapContext */
    ) external returns (uint256) {
        MockedExactOutputSwap[] storage mockedSwaps = nextExactOutputSwap[fromToken];
        for (uint256 i = 0; i < mockedSwaps.length; i++) {
            MockedExactOutputSwap memory mockedSwap = mockedSwaps[i];

            if (!mockedSwap.isExecuted) {
                // Transfer in the fromToken
                SafeERC20.safeTransferFrom(fromToken, msg.sender, address(this), mockedSwap.fromAmount);

                // Deal the output amount to the sender
                deal(address(mockedSwap.toToken), msg.sender, mockedSwap.toToken.balanceOf(msg.sender) + outputAmount);

                // Set the swap as executed
                mockedSwaps[i].isExecuted = true;

                return mockedSwap.fromAmount;
            }
        }

        revert("MockSwapper: No mocked exact output swap set");
    }
}
