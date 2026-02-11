// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

interface IMultiTokenMerkleDistributor {
    // Returns the addresses of the tokens distributed by this contract.
    function tokenList(uint256) external view returns (address);
    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoot() external view returns (bytes32);
    // Returns the address entrusted to clawback funds after the constructor-defined claim window elapses.
    function admin() external view returns (address);
    // Returns the block at which the admin may clawback funds.
    function withdrawableAt() external view returns (uint256);
    // Returns true if the index has been marked claimed.
    function isClaimed(uint256 index) external view returns (bool);
    // Claim the given amounts of tokens for the account. Reverts if the inputs are invalid.
    function claim(
        uint256 index,
        address account,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata merkleProof
    ) external;
    // Allows the admin to claw back the remaining balance of each token.
    function withdrawUnclaimed(
        address[] calldata tokens,
        address to
    ) external;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, address[] tokens, uint256[] amounts);
}
