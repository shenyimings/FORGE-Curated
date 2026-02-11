// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IQuoterV2 {
    /// @notice Returns the amount out received for a given exact input swap
    /// without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for
    /// each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that
    /// the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    )
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );
}
