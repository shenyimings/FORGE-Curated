// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Aerodrome Slipstream Factory Interface
/// @notice Factory for creating Aerodrome Slipstream pools
interface IAerodromeSlipstreamFactory {
    /// @notice Returns the pool address for a given pair of tokens and a tick spacing, or address 0 if it does not exist
    /// @param tokenA One token of the pool
    /// @param tokenB The other token of the pool
    /// @param tickSpacing The tick spacing of the pool
    /// @return pool The pool address
    function getPool(
        address tokenA,
        address tokenB,
        int24 tickSpacing
    ) external view returns (address pool);

    /// @notice Creates a pool for the given two tokens and tick spacing
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param tickSpacing The desired tick spacing for the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool as a Q64.96
    /// @return pool The address of the newly created pool
    function createPool(
        address tokenA,
        address tokenB,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) external returns (address pool);

    /// @notice Returns the pool implementation address
    function poolImplementation() external view returns (address);

    /// @notice Returns the owner of the factory
    function owner() external view returns (address);

    /// @notice Emitted when a pool is created
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        int24 indexed tickSpacing,
        address pool
    );
}