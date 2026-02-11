// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title IAllowedCalldataChecker
/// @author P2P Validator <info@p2p.org>
/// @notice Interface for checking if a calldata is allowed
interface IAllowedCalldataChecker {

    /// @notice Checks if the calldata is allowed
    /// @param _target The address of the yield protocol
    /// @param _selector The selector of the function
    /// @param _calldataAfterSelector The calldata after the selector
    function checkCalldata(
        address _target,
        bytes4 _selector,
        bytes calldata _calldataAfterSelector
    ) external view;
}
