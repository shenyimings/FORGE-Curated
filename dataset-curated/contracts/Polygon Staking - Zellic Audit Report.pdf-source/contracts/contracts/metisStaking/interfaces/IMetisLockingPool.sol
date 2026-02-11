// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IMetisLockingPool {
    enum Status {
        Unavailabe,
        Inactive,
        Active,
        Unlocked
    }

    function sequencers(
        uint256 _seqId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 reward,
            uint256 activationBatch,
            uint256 updatedBatch,
            uint256 deactivationBatch,
            uint256 deactivationTime,
            uint256 unlockClaimTime,
            uint256 nonce,
            address owner,
            address signer,
            bytes memory pubkey,
            address rewardRecipient,
            Status status
        );

    function seqOwners(address _owner) external view returns (uint256 seqId);

    function currentBatch() external view returns (uint256);

    function exitDelayPeriod() external view returns (uint256);

    function lockWithRewardRecipient(
        address _signer,
        address _rewardRecipient,
        uint256 _amount,
        bytes calldata _signerPubkey
    ) external;

    function relock(uint256 _seqId, uint256 _amount, bool _lockReward) external;

    function withdraw(uint256 _seqId, uint256 _amount) external;

    function withdrawRewards(uint256 _seqId, uint32 _l2Gas) external payable;

    function unlock(uint256 _seqId, uint32 _l2Rewards) external payable;

    function unlockClaim(uint256 _seqId, uint32 _l2Gas) external payable;
}
