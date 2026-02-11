// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IImmutableOwnableTrait} from "../interfaces/base/IImmutableOwnableTrait.sol";

/// @title Immutable ownable trait
/// @notice Contract that adds immutable owner functionality when inherited
abstract contract ImmutableOwnableTrait is IImmutableOwnableTrait {
    /// @notice The immutable owner address
    address public immutable override owner;

    /// @notice Modifier to restrict access to owner only
    modifier onlyOwner() {
        if (msg.sender != owner) revert CallerIsNotOwnerException(msg.sender);
        _;
    }

    /// @notice Constructor
    /// @param owner_ Immutable owner address
    constructor(address owner_) {
        owner = owner_;
    }
}
