// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IBalancerV3Router {
    /// @notice Adds liquidity to a pool with proportional token amounts, receiving an exact amount of pool tokens.
    /// @param pool Address of the liquidity pool
    /// @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
    /// @param exactBptAmountOut Exact amount of pool tokens to be received
    /// @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
    /// @param userData Additional (optional) data sent with the request to add liquidity
    /// @return amountsIn Actual amounts of tokens added, sorted in token registration order
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        returns (uint256[] memory amountsIn);

    /// @notice Removes liquidity with proportional token amounts from a pool, burning an exact pool token amount.
    /// @param pool Address of the liquidity pool
    /// @param exactBptAmountIn Exact amount of pool tokens provided
    /// @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
    /// @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
    /// @param userData Additional (optional) data sent with the request to remove liquidity
    /// @return amountsOut Actual amounts of tokens received, sorted in token registration order
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        returns (uint256[] memory amountsOut);
}
