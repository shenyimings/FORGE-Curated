// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../interfaces/ISFC.sol";

contract SFCMock is ISFC {
    struct Validator {
        uint256 status;
        uint256 deactivatedTime;
        uint256 deactivatedEpoch;
        uint256 receivedStake;
        uint256 createdEpoch;
        uint256 createdTime;
        address auth;
    }

    struct EpochSnapshot {
        mapping(uint256 => uint256) receivedStake;
        mapping(uint256 => uint256) accumulatedRewardPerToken;
        mapping(uint256 => uint256) accumulatedUptime;
        mapping(uint256 => uint256) accumulatedOriginatedTxsFee;
        mapping(uint256 => uint256) offlineTime;
        mapping(uint256 => uint256) offlineBlocks;
        uint256[] validatorIDs;
        uint256 endTime;
        uint256 epochFee;
        uint256 totalBaseRewardWeight;
        uint256 totalTxRewardWeight;
        uint256 baseRewardPerSecond;
        uint256 totalStake;
        uint256 totalSupply;
    }

    struct LockedDelegation {
        uint256 lockedStake;
        uint256 fromEpoch;
        uint256 endTime;
        uint256 duration;
    }

    struct Rewards {
        uint256 lockupExtraReward;
        uint256 lockupBaseReward;
        uint256 unlockedReward;
    }

    uint256 private _currentEpoch;
    uint256 private _currentSealedEpoch;

    mapping(uint256 => uint256) private _pendingWithdrawal;

    mapping(uint256 => Validator) public getValidator;
    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;
    mapping(address => mapping(uint256 => uint256)) public getStake;
    mapping(address => mapping(uint256 => Rewards)) public getStashedLockupRewards;
    mapping(address => mapping(uint256 => LockedDelegation)) public getLockupInfo;

    mapping(address => mapping(uint256 => uint256)) public _pendingRewards;
    mapping(address => mapping(uint256 => bool)) public _isLockedUp;
    mapping(address => mapping(uint256 => uint256)) public _stashedRewardsUntilEpoch;

    mapping(uint256 => mapping(uint256 => uint256)) public epochAccumulatedRewardPerToken;

    // validator ID -> slashing refund ratio (allows to withdraw slashed stake)
    mapping(uint256 validatorID => uint256 refundRatio) public slashingRefundRatio;
    mapping(uint256 validatorID => bool isCheater) public cheaters;

    function currentEpoch() external view override returns (uint256) {
        return _currentEpoch;
    }

    function setCurrentEpoch(uint256 __currentEpoch) external {
        _currentEpoch = __currentEpoch;
    }

    function addStake(address delegator, uint256 toValidatorID, uint256 stake) public {
        getStake[delegator][toValidatorID] += stake;
    }

    function setPendingRewards(address delegator, uint256 toValidatorID, uint256 rewards) external payable {
        require(msg.value == rewards, "Insufficient funds sent");
        _pendingRewards[delegator][toValidatorID] = rewards;
    }

    function pendingRewards(address delegator, uint256 toValidatorID) external view override returns (uint256) {
        return _pendingRewards[delegator][toValidatorID];
    }

    function delegate(uint256 toValidatorID) external payable override {
        addStake(msg.sender, toValidatorID, msg.value);
    }

    function claimRewards(uint256 toValidatorID) external override {
        uint256 rewards = _pendingRewards[msg.sender][toValidatorID];
        _pendingRewards[msg.sender][toValidatorID] = 0;
        payable(msg.sender).transfer(rewards);
    }

    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) external override {
        getStake[msg.sender][toValidatorID] -= amount;
        _pendingWithdrawal[wrID] = amount;
    }

    function withdraw(uint256 toValidatorID, uint256 wrID) external override {
        uint256 amount = _pendingWithdrawal[wrID];
        _pendingWithdrawal[wrID] = 0;

        uint256 penalty = getSlashingPenalty(amount, cheaters[toValidatorID], slashingRefundRatio[toValidatorID]);

        if (amount <= penalty) {
            revert StakeIsFullySlashed();
        }

        payable(msg.sender).transfer(amount - penalty);
    }

    /// Get slashing penalty for a stake.
    function getSlashingPenalty(uint256 amount, bool isCheater, uint256 refundRatio)
        internal
        pure
        returns (uint256 penalty)
    {
        if (!isCheater || refundRatio >= 1e18) {
            return 0;
        }
        // round penalty upwards (ceiling) to prevent dust amount attacks
        penalty = (amount * (1e18 - refundRatio)) / 1e18 + 1;
        if (penalty > amount) {
            return amount;
        }
        return penalty;
    }

    function setCheater(uint256 validatorID, bool _isCheater) external {
        cheaters[validatorID] = _isCheater;
    }

    function setSlashRefundRatio(uint256 validatorID, uint256 _refundRatio) external {
        slashingRefundRatio[validatorID] = _refundRatio;
    }

    function getSelfStake(uint256 validatorID) external view returns (uint256) {
        return 1;
    }

    function isSlashed(uint256 validatorID) external view returns (bool) {
        return cheaters[validatorID];
    }
}
