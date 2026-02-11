// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Internal imports
import {IAerodromeRouter} from "../interfaces/periphery/IAerodromeRouter.sol";
import {IAerodromeSlipstreamRouter} from "../interfaces/periphery/IAerodromeSlipstreamRouter.sol";
import {IUniswapSwapRouter02} from "../interfaces/periphery/IUniswapSwapRouter02.sol";
import {IUniswapV2Router02} from "../interfaces/periphery/IUniswapV2Router02.sol";
import {ISwapAdapter} from "../interfaces/periphery/ISwapAdapter.sol";

/**
 * @dev The SwapAdapter contract is a periphery contract that facilitates the use of various DEXes for swaps.
 */
contract SwapAdapter is ISwapAdapter {
    /// @inheritdoc ISwapAdapter
    function swapExactInput(
        IERC20 inputToken,
        uint256 inputAmount,
        uint256 minOutputAmount,
        SwapContext memory swapContext
    ) external returns (uint256) {
        SafeERC20.safeTransferFrom(inputToken, msg.sender, address(this), inputAmount);

        uint256 outputAmount = 0;
        if (swapContext.exchange == Exchange.AERODROME) {
            outputAmount = _swapExactInputAerodrome(inputAmount, minOutputAmount, swapContext);
        } else if (swapContext.exchange == Exchange.AERODROME_SLIPSTREAM) {
            outputAmount = _swapExactInputAerodromeSlipstream(inputAmount, minOutputAmount, swapContext);
        } else if (swapContext.exchange == Exchange.UNISWAP_V2) {
            outputAmount = _swapExactInputUniV2(inputAmount, minOutputAmount, swapContext);
        } else if (swapContext.exchange == Exchange.UNISWAP_V3) {
            outputAmount = _swapExactInputUniV3(inputAmount, minOutputAmount, swapContext);
        }

        return outputAmount;
    }

    /// @inheritdoc ISwapAdapter
    function swapExactOutput(
        IERC20 inputToken,
        uint256 outputAmount,
        uint256 maxInputAmount,
        SwapContext memory swapContext
    ) external returns (uint256) {
        SafeERC20.safeTransferFrom(inputToken, msg.sender, address(this), maxInputAmount);

        uint256 inputAmount = 0;
        if (swapContext.exchange == Exchange.AERODROME) {
            inputAmount = _swapExactOutputAerodrome(outputAmount, maxInputAmount, swapContext);
        } else if (swapContext.exchange == Exchange.AERODROME_SLIPSTREAM) {
            inputAmount = _swapExactOutputAerodromeSlipstream(outputAmount, maxInputAmount, swapContext);
        } else if (swapContext.exchange == Exchange.UNISWAP_V2) {
            inputAmount = _swapExactOutputUniV2(outputAmount, maxInputAmount, swapContext);
        } else if (swapContext.exchange == Exchange.UNISWAP_V3) {
            inputAmount = _swapExactOutputUniV3(outputAmount, maxInputAmount, swapContext);
        }

        // Transfer back excess inputToken not used for the swap to the sender
        uint256 excessInputAmount = maxInputAmount - inputAmount;

        // slither-disable-next-line timestamp
        if (excessInputAmount > 0) {
            SafeERC20.safeTransfer(inputToken, msg.sender, excessInputAmount);
        }

        return inputAmount;
    }

    function _swapAerodrome(
        uint256 inputAmount,
        uint256 minOutputAmount,
        address receiver,
        address aerodromeRouter,
        address aerodromePoolFactory,
        address[] memory path
    ) internal returns (uint256 outputAmount) {
        IAerodromeRouter.Route[] memory routes = _generateAerodromeRoutes(path, aerodromePoolFactory);

        SafeERC20.forceApprove(IERC20(path[0]), address(aerodromeRouter), inputAmount);
        uint256[] memory amounts = IAerodromeRouter(aerodromeRouter).swapExactTokensForTokens(
            inputAmount, minOutputAmount, routes, receiver, block.timestamp
        );

        return amounts[amounts.length - 1];
    }

    function _swapExactInputAerodrome(uint256 inputAmount, uint256 minOutputAmount, SwapContext memory swapContext)
        internal
        returns (uint256 outputAmount)
    {
        return _swapAerodrome(
            inputAmount,
            minOutputAmount,
            msg.sender,
            swapContext.exchangeAddresses.aerodromeRouter,
            swapContext.exchangeAddresses.aerodromePoolFactory,
            swapContext.path
        );
    }

    function _swapExactInputAerodromeSlipstream(
        uint256 inputAmount,
        uint256 minOutputAmount,
        SwapContext memory swapContext
    ) internal returns (uint256 outputAmount) {
        // Check that the number of routes is equal to the number of tick spacings plus one, as required by Aerodrome Slipstream
        if (swapContext.path.length != swapContext.tickSpacing.length + 1) revert InvalidNumTicks();

        IAerodromeSlipstreamRouter aerodromeSlipstreamRouter =
            IAerodromeSlipstreamRouter(swapContext.exchangeAddresses.aerodromeSlipstreamRouter);

        SafeERC20.forceApprove(IERC20(swapContext.path[0]), address(aerodromeSlipstreamRouter), inputAmount);

        if (swapContext.path.length == 2) {
            IAerodromeSlipstreamRouter.ExactInputSingleParams memory swapParams = IAerodromeSlipstreamRouter
                .ExactInputSingleParams({
                tokenIn: swapContext.path[0],
                tokenOut: swapContext.path[1],
                tickSpacing: swapContext.tickSpacing[0],
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: inputAmount,
                amountOutMinimum: minOutputAmount,
                sqrtPriceLimitX96: 0
            });

            return aerodromeSlipstreamRouter.exactInputSingle(swapParams);
        } else {
            IAerodromeSlipstreamRouter.ExactInputParams memory swapParams = IAerodromeSlipstreamRouter.ExactInputParams({
                path: swapContext.encodedPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: inputAmount,
                amountOutMinimum: minOutputAmount
            });

            return aerodromeSlipstreamRouter.exactInput(swapParams);
        }
    }

    function _swapExactInputUniV2(uint256 inputAmount, uint256 minOutputAmount, SwapContext memory swapContext)
        internal
        returns (uint256 outputAmount)
    {
        IUniswapV2Router02 uniswapV2Router02 = IUniswapV2Router02(swapContext.exchangeAddresses.uniswapV2Router02);

        SafeERC20.forceApprove(IERC20(swapContext.path[0]), address(uniswapV2Router02), inputAmount);

        uint256[] memory amounts = uniswapV2Router02.swapExactTokensForTokens(
            inputAmount, minOutputAmount, swapContext.path, msg.sender, block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    function _swapExactInputUniV3(uint256 inputAmount, uint256 minOutputAmount, SwapContext memory swapContext)
        internal
        returns (uint256 outputAmount)
    {
        // Check that the number of fees is equal to the number of paths minus one, as required by Uniswap V3
        if (swapContext.path.length != swapContext.fees.length + 1) revert InvalidNumFees();

        IUniswapSwapRouter02 uniswapSwapRouter02 =
            IUniswapSwapRouter02(swapContext.exchangeAddresses.uniswapSwapRouter02);

        SafeERC20.forceApprove(IERC20(swapContext.path[0]), address(uniswapSwapRouter02), inputAmount);

        if (swapContext.path.length == 2) {
            IUniswapSwapRouter02.ExactInputSingleParams memory params = IUniswapSwapRouter02.ExactInputSingleParams({
                tokenIn: swapContext.path[0],
                tokenOut: swapContext.path[1],
                fee: swapContext.fees[0],
                recipient: msg.sender,
                amountIn: inputAmount,
                amountOutMinimum: minOutputAmount,
                sqrtPriceLimitX96: 0
            });

            return uniswapSwapRouter02.exactInputSingle(params);
        } else {
            IUniswapSwapRouter02.ExactInputParams memory params = IUniswapSwapRouter02.ExactInputParams({
                path: swapContext.encodedPath,
                recipient: msg.sender,
                amountIn: inputAmount,
                amountOutMinimum: minOutputAmount
            });

            return uniswapSwapRouter02.exactInput(params);
        }
    }

    function _swapExactOutputAerodrome(uint256 outputAmount, uint256 maxInputAmount, SwapContext memory swapContext)
        internal
        returns (uint256 inputAmount)
    {
        uint256 outputAmountReceived = _swapAerodrome(
            maxInputAmount,
            outputAmount,
            address(this),
            swapContext.exchangeAddresses.aerodromeRouter,
            swapContext.exchangeAddresses.aerodromePoolFactory,
            swapContext.path
        );

        // We only need outputAmount of the received tokens, so we swap the surplus back to the inputToken and send it back to sender
        // slither-disable-next-line timestamp
        if (outputAmountReceived > outputAmount) {
            uint256 surplusInputAmount = _swapAerodrome(
                outputAmountReceived - outputAmount,
                0,
                address(this),
                swapContext.exchangeAddresses.aerodromeRouter,
                swapContext.exchangeAddresses.aerodromePoolFactory,
                _reversePath(swapContext.path)
            );

            SafeERC20.safeTransfer(IERC20(swapContext.path[swapContext.path.length - 1]), msg.sender, outputAmount);

            return maxInputAmount - surplusInputAmount;
        } else {
            SafeERC20.safeTransfer(IERC20(swapContext.path[swapContext.path.length - 1]), msg.sender, outputAmount);

            return maxInputAmount;
        }
    }

    function _swapExactOutputAerodromeSlipstream(
        uint256 outputAmount,
        uint256 maxInputAmount,
        SwapContext memory swapContext
    ) internal returns (uint256 inputAmount) {
        // Check that the number of routes is equal to the number of tick spacings plus one, as required by Aerodrome Slipstream
        if (swapContext.path.length != swapContext.tickSpacing.length + 1) revert InvalidNumTicks();

        IAerodromeSlipstreamRouter aerodromeSlipstreamRouter =
            IAerodromeSlipstreamRouter(swapContext.exchangeAddresses.aerodromeSlipstreamRouter);

        SafeERC20.forceApprove(IERC20(swapContext.path[0]), address(aerodromeSlipstreamRouter), maxInputAmount);

        if (swapContext.path.length == 2) {
            IAerodromeSlipstreamRouter.ExactOutputSingleParams memory swapParams = IAerodromeSlipstreamRouter
                .ExactOutputSingleParams({
                tokenIn: swapContext.path[0],
                tokenOut: swapContext.path[1],
                tickSpacing: swapContext.tickSpacing[0],
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: outputAmount,
                amountInMaximum: maxInputAmount,
                sqrtPriceLimitX96: 0
            });
            return aerodromeSlipstreamRouter.exactOutputSingle(swapParams);
        } else {
            IAerodromeSlipstreamRouter.ExactOutputParams memory swapParams = IAerodromeSlipstreamRouter
                .ExactOutputParams({
                // This should be the encoded reversed path as exactOutput expects the path to be in reverse order
                path: swapContext.encodedPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: outputAmount,
                amountInMaximum: maxInputAmount
            });
            return aerodromeSlipstreamRouter.exactOutput(swapParams);
        }
    }

    function _swapExactOutputUniV2(uint256 outputAmount, uint256 maxInputAmount, SwapContext memory swapContext)
        internal
        returns (uint256 inputAmount)
    {
        IUniswapV2Router02 uniswapV2Router02 = IUniswapV2Router02(swapContext.exchangeAddresses.uniswapV2Router02);

        SafeERC20.forceApprove(IERC20(swapContext.path[0]), address(uniswapV2Router02), maxInputAmount);

        return uniswapV2Router02.swapTokensForExactTokens(
            outputAmount, maxInputAmount, swapContext.path, msg.sender, block.timestamp
        )[0];
    }

    function _swapExactOutputUniV3(uint256 outputAmount, uint256 maxInputAmount, SwapContext memory swapContext)
        internal
        returns (uint256 inputAmount)
    {
        // Check that the number of fees is equal to the number of paths minus one, as required by Uniswap V3
        if (swapContext.path.length != swapContext.fees.length + 1) revert InvalidNumFees();

        IUniswapSwapRouter02 uniswapSwapRouter02 =
            IUniswapSwapRouter02(swapContext.exchangeAddresses.uniswapSwapRouter02);

        SafeERC20.forceApprove(IERC20(swapContext.path[0]), address(uniswapSwapRouter02), maxInputAmount);

        if (swapContext.path.length == 2) {
            IUniswapSwapRouter02.ExactOutputSingleParams memory params = IUniswapSwapRouter02.ExactOutputSingleParams({
                tokenIn: swapContext.path[0],
                tokenOut: swapContext.path[1],
                fee: swapContext.fees[0],
                recipient: msg.sender,
                amountOut: outputAmount,
                amountInMaximum: maxInputAmount,
                sqrtPriceLimitX96: 0
            });
            return uniswapSwapRouter02.exactOutputSingle(params);
        } else {
            IUniswapSwapRouter02.ExactOutputParams memory params = IUniswapSwapRouter02.ExactOutputParams({
                // This should be the encoded reversed path as exactOutput expects the path to be in reverse order
                path: swapContext.encodedPath,
                recipient: msg.sender,
                amountOut: outputAmount,
                amountInMaximum: maxInputAmount
            });
            return uniswapSwapRouter02.exactOutput(params);
        }
    }

    /// @notice Generate the array of Routes as required by the Aerodrome router
    function _generateAerodromeRoutes(address[] memory path, address aerodromePoolFactory)
        internal
        pure
        returns (IAerodromeRouter.Route[] memory routes)
    {
        routes = new IAerodromeRouter.Route[](path.length - 1);
        for (uint256 i = 0; i < path.length - 1; i++) {
            routes[i] = IAerodromeRouter.Route(path[i], path[i + 1], false, aerodromePoolFactory);
        }
    }

    /// @notice Reverses a path of addresses
    function _reversePath(address[] memory path) internal pure returns (address[] memory reversedPath) {
        reversedPath = new address[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            reversedPath[i] = path[path.length - i - 1];
        }
    }
}
