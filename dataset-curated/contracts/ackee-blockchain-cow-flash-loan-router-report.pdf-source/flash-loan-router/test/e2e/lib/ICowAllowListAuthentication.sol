// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ICowAuthentication} from "src/vendored/ICowAuthentication.sol";

/// @notice An interface for CoW Protocol's sauthenticator contract that only
/// enumerates the functions needed for this project.
/// For more information, see the project's repository:
/// <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2AllowListAuthentication.sol>
interface ICowAllowListAuthentication is ICowAuthentication {
    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2AllowListAuthentication.sol#L80-L89>.
    function addSolver(address solver) external;
}
