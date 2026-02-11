// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.9.0;

/// @title IUniswapV2Pair Interface
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Minimal interface for our interactions with the Uniswap V2's Pair contract
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_);

    function token0() external view returns (address token0Address_);

    function token1() external view returns (address token1Address_);

    function totalSupply() external view returns (uint256 totalSupply_);
}
