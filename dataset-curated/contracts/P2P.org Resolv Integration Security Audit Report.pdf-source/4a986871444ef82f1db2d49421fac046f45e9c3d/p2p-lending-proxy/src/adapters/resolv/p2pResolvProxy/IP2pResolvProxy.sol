// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

/// @title Interface for the P2P Resolv proxy adapter
/// @notice Exposes Resolv specific helper flows to withdraw and claim on behalf of a client.
interface IP2pResolvProxy {
    /// @notice Withdraws a specific amount of USR on behalf of the client.
    /// @param _amount Amount of USR (in wei) requested by the client.
    function withdrawUSR(uint256 _amount) external;

    /// @notice Withdraws the entire USR balance held by the proxy for the client.
    function withdrawAllUSR() external;

    /// @notice Initiates a delayed withdrawal request for RESOLV from the staking contract.
    /// @param _amount Amount of staked RESOLV shares to mark for withdrawal.
    function initiateWithdrawalRESOLV(uint256 _amount) external;

    /// @notice Completes a pending RESOLV withdrawal, distributing proceeds per the fee split.
    function withdrawRESOLV() external;

    /// @notice Claims rewards from the Resolv StakedTokenDistributor on behalf of the client/operator.
    /// @param _index Index of the Merkle proof entry.
    /// @param _amount Amount of rewards being claimed.
    /// @param _merkleProof Merkle proof validating the claim eligibility.
    function claimStakedTokenDistributor(
        uint256 _index,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    )
    external;

    /// @notice Emitted when rewards are claimed from the distributor.
    /// @param _amount Amount of rewards paid out for the claim.
    event P2pResolvProxy__Claimed(uint256 _amount);
}
