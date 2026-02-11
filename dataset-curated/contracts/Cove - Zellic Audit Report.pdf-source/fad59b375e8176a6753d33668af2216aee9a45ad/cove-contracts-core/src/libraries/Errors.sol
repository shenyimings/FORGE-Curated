// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title Errors
/// @notice Library containing shared custom errors the protocol may revert with.
// solhint-disable var-name-mixedcase
library Errors {
    /// @notice Thrown when an empty address is given as parameter to a function that does not allow it.
    error ZeroAddress();

    /// @notice Thrown when an 0 is given as amount parameter to a function that does not allow it.
    error ZeroAmount();
}
