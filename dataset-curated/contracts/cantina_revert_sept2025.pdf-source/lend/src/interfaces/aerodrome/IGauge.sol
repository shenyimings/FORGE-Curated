// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Aerodrome Gauge Interface
/// @notice Interface for Aerodrome gauge contracts that handle LP staking and rewards
interface IGauge {
    /// @notice Deposit LP tokens (NFT positions) into the gauge
    /// @param tokenId The NFT token ID to deposit
    function deposit(uint256 tokenId) external;

    /// @notice Deposit LP tokens for another user
    /// @param tokenId The NFT token ID to deposit
    /// @param recipient The address that will receive the staked position
    function depositFor(uint256 tokenId, address recipient) external;

    /// @notice Withdraw LP tokens from the gauge
    /// @param tokenId The NFT token ID to withdraw
    function withdraw(uint256 tokenId) external;

    /// @notice Get pending rewards for a user
    /// @param user The user address
    /// @return amount The amount of pending rewards
    function earned(address user) external view returns (uint256 amount);

    /// @notice Claim rewards for all positions owned by msg.sender
    function getReward() external;

    /// @notice Claim rewards for a specific user
    /// @param user The user to claim rewards for
    function getReward(address user) external;
    
    /// @notice Claim rewards for a specific NFT token ID
    /// @param tokenId The NFT token ID to claim rewards for
    function getReward(uint256 tokenId) external;

    /// @notice Get the total supply staked in the gauge
    /// @return The total staked amount
    function totalSupply() external view returns (uint256);

    /// @notice Get the balance of a specific user
    /// @param user The user address
    /// @return The user's staked balance
    function balanceOf(address user) external view returns (uint256);

    /// @notice Get staked NFT token IDs for a user
    /// @param user The user address
    /// @return tokenIds Array of staked token IDs
    function stakedTokenIds(address user) external view returns (uint256[] memory tokenIds);

    /// @notice Check if a token ID is staked
    /// @param tokenId The NFT token ID
    /// @return Whether the token is staked
    function isStaked(uint256 tokenId) external view returns (bool);

    /// @notice Get the reward token address (AERO)
    /// @return The reward token address
    function rewardToken() external view returns (address);

    /// @notice Get the LP token address (position manager)
    /// @return The LP token address
    function stake() external view returns (address);

    /// @notice Emitted when tokens are deposited
    event Deposit(address indexed user, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    event Withdraw(address indexed user, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when rewards are claimed
    event RewardPaid(address indexed user, uint256 reward);
}