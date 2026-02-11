// SPDX-License-Identifier: UNLICENSED
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ISwapRouter02} from "../interfaces/ISwapRouter02.sol";
import {BytesLib, Path} from "./Path.sol";

pragma solidity >= 0.8.18;

library SkipSwapRouter {
    using SafeERC20 for IERC20;
    using Path for bytes;

    error InsufficientOutputAmount();
    error NativePaymentFailed();

    enum SwapCommands {
        ExactInputSingle,
        ExactInput,
        ExactTokensForTokens,
        ExactOutputSingle,
        ExactOutput,
        TokensForExactTokens
    }

    function multiSwap(
        ISwapRouter02 router,
        address destination,
        IERC20 inputToken,
        uint256 amountIn,
        bytes[] memory swaps
    ) external returns (IERC20 outputToken, uint256 amountOut) {
        outputToken = inputToken;
        amountOut = amountIn;

        uint256 numSwaps = swaps.length;
        for (uint256 i; i < numSwaps; i++) {
            // The output token and amount of each iteration is the input token and amount of the next.
            (outputToken, amountOut) = swap(router, destination, outputToken, amountOut, swaps[i]);
        }
    }

    function swap(ISwapRouter02 router, address destination, IERC20 inputToken, uint256 amountIn, bytes memory payload)
        public
        returns (IERC20 outputToken, uint256 outputAmount)
    {
        (SwapCommands command, address tokenOut, uint256 amountOut, bytes memory swapData) =
            abi.decode(payload, (SwapCommands, address, uint256, bytes));

        outputToken = IERC20(tokenOut);

        uint256 preBalIn = inputToken.balanceOf(address(this)) - amountIn;
        uint256 preBalOut = outputToken.balanceOf(address(this));

        inputToken.forceApprove(address(router), amountIn);

        if (command == SwapCommands.ExactInputSingle) {
            ISwapRouter02.ExactInputSingleParams memory params;
            params.tokenIn = address(inputToken);
            params.tokenOut = tokenOut;
            params.recipient = address(this);
            params.amountIn = amountIn;
            params.amountOutMinimum = amountOut;

            (params.fee, params.sqrtPriceLimitX96) = abi.decode(swapData, (uint24, uint160));

            router.exactInputSingle(params);
        } else if (command == SwapCommands.ExactInput) {
            ISwapRouter02.ExactInputParams memory params;
            params.path = _fixPath(address(inputToken), tokenOut, swapData);
            params.path = swapData;
            params.recipient = address(this);
            params.amountIn = amountIn;
            params.amountOutMinimum = amountOut;

            router.exactInput(params);
        } else if (command == SwapCommands.ExactTokensForTokens) {
            address[] memory path = _fixPath(address(inputToken), tokenOut, abi.decode(swapData, (address[])));

            router.swapExactTokensForTokens(amountIn, amountOut, path, address(this));
        } else if (command == SwapCommands.ExactOutputSingle) {
            ISwapRouter02.ExactOutputSingleParams memory params;
            params.tokenIn = address(inputToken);
            params.tokenOut = tokenOut;
            params.recipient = address(this);
            params.amountInMaximum = amountIn;
            params.amountOut = amountOut;

            (params.fee, params.sqrtPriceLimitX96) = abi.decode(swapData, (uint24, uint160));

            router.exactOutputSingle(params);
        } else if (command == SwapCommands.ExactOutput) {
            ISwapRouter02.ExactOutputParams memory params;
            params.path = _fixPath(tokenOut, address(inputToken), swapData);
            params.path = swapData;
            params.recipient = address(this);
            params.amountInMaximum = amountIn;
            params.amountOut = amountOut;

            router.exactOutput(params);
        } else if (command == SwapCommands.TokensForExactTokens) {
            address[] memory path = _fixPath(address(inputToken), address(tokenOut), abi.decode(swapData, (address[])));

            router.swapTokensForExactTokens(amountOut, amountIn, path, address(this));
        }

        outputAmount = outputToken.balanceOf(address(this)) - preBalOut;
        if (outputAmount < amountOut) {
            revert InsufficientOutputAmount();
        }

        uint256 dust = inputToken.balanceOf(address(this)) - preBalIn;
        if (dust != 0) {
            inputToken.forceApprove(address(router), 0);
            inputToken.safeTransfer(destination, dust);
        }
    }

    function sendNative(address token, uint256 amount, address destination) external {
        // Unwrap native token.
        IWETH weth = IWETH(token);
        weth.withdraw(amount);

        // Send it unwrapped to the destination
        (bool success,) = destination.call{value: amount}("");

        if (!success) {
            revert NativePaymentFailed();
        }
    }

    function _fixPath(address tokenA, address tokenB, bytes memory path) internal pure returns (bytes memory) {
        (address decodedA,,) = path.decodeFirstPool();
        if (decodedA != tokenA) {
            path = BytesLib.concat(BytesLib.toBytes(tokenA), BytesLib.slice(path, 20, path.length - 20));
        }

        (, address decodedB,) = path.decodeLastPool();
        if (decodedB != tokenB) {
            path = BytesLib.concat(BytesLib.slice(path, 0, path.length - 20), BytesLib.toBytes(tokenB));
        }

        return path;
    }

    function _fixPath(address tokenA, address tokenB, address[] memory path) internal pure returns (address[] memory) {
        if (path[0] != tokenA) {
            path[0] = tokenA;
        }

        uint256 lastElement = path.length - 1;
        if (path[lastElement] != tokenB) {
            path[lastElement] = tokenB;
        }

        return path;
    }
}
