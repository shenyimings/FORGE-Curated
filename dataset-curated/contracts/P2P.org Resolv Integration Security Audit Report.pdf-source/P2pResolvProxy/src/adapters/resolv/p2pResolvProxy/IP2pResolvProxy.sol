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

    /// @notice Claims accrued reward tokens directly from ResolvStaking and splits them per the fee schedule.
    function claimRewardTokens() external;

    function setStakedTokenDistributor(address _stakedTokenDistributor) external;

    function getStakedTokenDistributor() external view returns (address);

    /// @notice Emitted when rewards are claimed from the distributor.
    /// @param _amount Amount of rewards paid out for the claim.
    event P2pResolvProxy__Claimed(uint256 _amount);

    /// @notice Emitted when RESOLV is deposited into ResolvStaking via the proxy.
    /// @param amount Amount of RESOLV deposited on behalf of the client.
    event P2pResolvProxy__ResolvDeposited(uint256 amount);

    /// @notice Emitted when a RESOLV withdrawal without rewards is forwarded directly to the client.
    /// @param caller Address that triggered the withdrawal completion.
    event P2pResolvProxy__ResolvPrincipalWithdrawal(address indexed caller);

    /// @notice Emitted when staking reward tokens are claimed and split.
    /// @param token Reward token address.
    /// @param amount Total reward amount claimed for `token`.
    /// @param p2pAmount Portion forwarded to the P2P treasury.
    /// @param clientAmount Portion forwarded to the client.
    event P2pResolvProxy__RewardTokensClaimed(
        address indexed token,
        uint256 amount,
        uint256 p2pAmount,
        uint256 clientAmount
    );

    /// @notice Emitted when a claimed airdrop withdrawal is processed and distributed.
    /// @param expectedRewardAmount The tracked pending reward amount from the distributor.
    /// @param actualRewardAmount Actual RESOLV amount received in the withdrawal.
    /// @param p2pAmount Portion of the reward sent to the treasury.
    /// @param clientAmount Portion of the reward sent to the client.
    /// @param principalForwarded The principal portion released to the client.
    event P2pResolvProxy__DistributorRewardsReleased(
        uint256 expectedRewardAmount,
        uint256 actualRewardAmount,
        uint256 p2pAmount,
        uint256 clientAmount,
        uint256 principalForwarded
    );

    /// @notice Sweeps accumulated reward tokens from the proxy to the client.
    /// @param _token Address of the ERC-20 token to sweep.
    function sweepRewardToken(address _token) external;

    /// @notice Emitted when the staked token distributor address is updated.
    /// @param previousStakedTokenDistributor The previous distributor address.
    /// @param newStakedTokenDistributor The new distributor address.
    event P2pResolvProxy__StakedTokenDistributorUpdated(
        address indexed previousStakedTokenDistributor,
        address indexed newStakedTokenDistributor
    );

    /// @notice Emitted when reward tokens are swept to the client.
    /// @param token The token address that was swept.
    /// @param amount The amount swept to the client.
    event P2pResolvProxy__RewardTokenSwept(address indexed token, uint256 amount);
}
