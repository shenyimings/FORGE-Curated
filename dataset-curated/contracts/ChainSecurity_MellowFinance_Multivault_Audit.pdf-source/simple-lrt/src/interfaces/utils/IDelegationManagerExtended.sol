// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * The current implementation of the IDelegationManager interface on the LayerZero GitHub repository lacks support for the pendingWithdrawals function,
 * despite on-chain support for this functionality. This extension addresses the limitation by augmenting the IDelegationManager interface to include
 * the missing pendingWithdrawals function.
 */
interface IDelegationManagerExtended {
    /// @notice Mapping: hash of withdrawal inputs, aka 'withdrawalRoot' => whether the withdrawal is pending
    function pendingWithdrawals(bytes32 withdrawalRoot) external view returns (bool);
}
