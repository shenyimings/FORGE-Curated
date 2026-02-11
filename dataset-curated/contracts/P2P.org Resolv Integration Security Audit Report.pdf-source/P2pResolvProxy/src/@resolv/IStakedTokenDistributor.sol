// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Allows anyone to claim a token if they exist in a merkle root.
interface IStakedTokenDistributor {
    event Claimed(uint256 index, address account, uint256 amount);
    event AddedToBlacklist(address account);
    event RemovedFromBlacklist(address account);
    event Withdrawn(address reciever);

    error AlreadyClaimed();
    error InvalidProof();
    error Blacklisted();
    error EndTimeInPast();
    error ClaimWindowFinished();
    error NoWithdrawDuringClaim();
    error ZeroAddress();

    // Claim the given amount of the token to the contract caller. Reverts if the inputs are invalid.
    function claim(uint256 index, uint256 amount, bytes32[] calldata merkleProof) external;
    // Returns true if the index has been marked claimed.
    function isClaimed(uint256 index) external view returns (bool);
}