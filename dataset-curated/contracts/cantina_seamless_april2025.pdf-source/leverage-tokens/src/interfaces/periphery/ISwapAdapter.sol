// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapAdapter {
    /// @notice The exchanges supported by SwapAdapter
    enum Exchange {
        AERODROME,
        AERODROME_SLIPSTREAM,
        UNISWAP_V2,
        UNISWAP_V3
    }

    /// @notice Addresses required to facilitate swaps on the supported exchanges
    struct ExchangeAddresses {
        address aerodromeRouter;
        address aerodromePoolFactory;
        address aerodromeSlipstreamRouter;
        address uniswapSwapRouter02;
        address uniswapV2Router02;
    }

    /// @notice Contextextual data required for a swap
    struct SwapContext {
        // The token swap path
        address[] path;
        // The encoded path of tokens to swap. Required by Uniswap V3 and Aerodrome Slipstream
        bytes encodedPath;
        // The fees to use for the swap. For Uniswap V3, fees are used to identify unique pools
        uint24[] fees;
        // The tick spacing to use for the swap. For Aerodrome Slipstream, tickSpacing is used to identify unique pools
        int24[] tickSpacing;
        // The exchange to use for the swap
        Exchange exchange;
        // The addresses required to facilitate swaps on the supported exchanges
        ExchangeAddresses exchangeAddresses;
    }

    /// @notice Error thrown when the number of ticks is invalid
    error InvalidNumTicks();

    /// @notice Error thrown when the number of fees is invalid
    error InvalidNumFees();

    /// @notice Swap tokens from the `inputToken` to the `outputToken` using the specified provider
    /// @dev The `outputToken` must be encoded in the `swapContext` path
    /// @param inputToken Token to swap from
    /// @param inputAmount Amount of tokens to swap
    /// @param minOutputAmount Minimum amount of tokens to receive
    /// @param swapContext Swap context to use for the swap (which exchange to use, the swap path, tick spacing, etc.)
    /// @return outputAmount Amount of tokens received
    function swapExactInput(
        IERC20 inputToken,
        uint256 inputAmount,
        uint256 minOutputAmount,
        SwapContext memory swapContext
    ) external returns (uint256 outputAmount);

    /// @notice Swap tokens from the `inputToken` to the `outputToken` using the specified provider
    /// @dev The `outputToken` must be encoded in the `swapContext` path
    /// @param inputToken Token to swap from
    /// @param outputAmount Amount of tokens to receive
    /// @param maxInputAmount Maximum amount of tokens to swap
    /// @param swapContext Swap context to use for the swap (which exchange to use, the swap path, tick spacing, etc.)
    /// @return inputAmount Amount of tokens swapped
    function swapExactOutput(
        IERC20 inputToken,
        uint256 outputAmount,
        uint256 maxInputAmount,
        SwapContext memory swapContext
    ) external returns (uint256 inputAmount);
}
