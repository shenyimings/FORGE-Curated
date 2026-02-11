// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";

/// @title Provides functions for deriving Aerodrome Slipstream pool addresses
library AerodromePoolAddress {
    /// @notice Deterministically computes the pool address given the factory and pool key
    /// @param factory The Aerodrome factory contract address
    /// @param implementation The pool implementation address from factory
    /// @param token0 The first token of the pool
    /// @param token1 The second token of the pool  
    /// @param tickSpacing The tick spacing of the pool
    /// @return pool The contract address of the pool
    function computeAddress(
        address factory,
        address implementation,
        address token0,
        address token1,
        int24 tickSpacing
    ) internal pure returns (address pool) {
        require(token0 < token1, "Token order");
        bytes32 salt = keccak256(abi.encode(token0, token1, tickSpacing));
        pool = Clones.predictDeterministicAddress(implementation, salt, factory);
    }
}