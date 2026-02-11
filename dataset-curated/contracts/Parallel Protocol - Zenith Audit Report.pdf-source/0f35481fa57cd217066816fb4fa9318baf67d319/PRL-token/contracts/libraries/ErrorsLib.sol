// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title ErrorsLib
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Library exposing all commun errors.
library ErrorsLib {
    /// @notice Thrown when the address is zero.
    error AddressZero();

    /// @notice Thrown when the msg length is invalid.
    error InvalidMsgLength();
}
