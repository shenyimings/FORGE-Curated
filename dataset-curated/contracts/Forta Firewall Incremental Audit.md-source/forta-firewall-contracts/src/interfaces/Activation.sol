// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

/// @notice Checkpoint activation modes.
enum Activation {
    /// @notice The default activation value for an unset checkpoint, which should mean "no security checks".
    Inactive,
    /// @notice The checkpoint is blocked by default.
    AlwaysBlocked,
    /// @notice Every call to the integrated function should require security checks.
    AlwaysActive,
    /// @notice Security checks are only required if a specific function argument exceeds the threshold.
    ConstantThreshold,
    /// @notice For adding up all intercepted values by the same checkpoint before comparing with the threshold.
    AccumulatedThreshold
}
