// SPDX-License-Identifier: LGPL-3.0-or-later

// Vendored from CoW DAO contracts with minor modifications:
// - Formatted code
// - Changed contract name
// <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/interfaces/GPv2Authentication.sol>

pragma solidity >=0.7.6 <0.9.0;

/// @title Gnosis Protocol v2 Authentication Interface
/// @author Gnosis Developers
interface ICowAuthentication {
    /// @dev determines whether the provided address is an authenticated solver.
    /// @param prospectiveSolver the address of prospective solver.
    /// @return true when prospectiveSolver is an authenticated solver, otherwise false.
    function isSolver(address prospectiveSolver) external view returns (bool);
}
