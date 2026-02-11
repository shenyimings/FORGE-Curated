// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title ISwapper
 * @notice Interface for token swapping functionality
 * @dev This interface defines the standard for swapping one token for another.
 * Implementations of this interface handle the actual swap logic and routing,
 * which may involve DEX integrations, aggregators, or other swap mechanisms.
 */
interface ISwapper {
    /**
     * @notice Emitted after a successful token swap
     */
    event Swap(address indexed assetIn, address indexed assetOut, uint256 amountIn, uint256 amountOut);

    /**
     * @notice Swaps one token for another
     * @dev This function performs a token swap from `assetIn` to `assetOut`.
     * The caller must transfer `amountIn` of `assetIn` to the swapper contract
     * before calling this function. The swapper will then send the resulting
     * `assetOut` tokens to the specified recipient.
     * @param assetIn The address of the input token to be swapped
     * @param amountIn The amount of input tokens to swap
     * @param assetOut The address of the output token to receive
     * @param minAmountOut The minimum amount of output tokens expected (slippage protection)
     * @param recipient The address that will receive the output tokens
     * @param swapperParams Additional data specific to the swap implementation (e.g., DEX router data, paths)
     * @return amountOut The actual amount of output tokens received from the swap
     */
    function swap(
        address assetIn,
        uint256 amountIn,
        address assetOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata swapperParams
    )
        external
        returns (uint256 amountOut);
}
