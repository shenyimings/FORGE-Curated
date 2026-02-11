// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title Restaker Reward Receiver Interface
/// @author Cap Labs
/// @notice Interface for contracts that can receive and distribute rewards from restaking
interface IRestakerRewardReceiver {
    /// @notice Distribute rewards accumulated by the agent borrowing
    /// @param _agent Agent address
    /// @param _token Token address
    function distributeRewards(address _agent, address _token) external;
}
