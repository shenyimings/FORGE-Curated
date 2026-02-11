// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

/// @title Immutable ownable trait interface
/// @notice Interface for contracts with immutable owner functionality
interface IImmutableOwnableTrait {
    error CallerIsNotOwnerException(address caller);

    /// @notice Returns the immutable owner address
    function owner() external view returns (address);
}
