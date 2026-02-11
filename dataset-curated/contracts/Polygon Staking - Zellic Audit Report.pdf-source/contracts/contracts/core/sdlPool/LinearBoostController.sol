// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Linear Boost Controller
 * @notice Handles boost calculations
 */
contract LinearBoostController is Ownable {
    uint64 public minLockingDuration;
    uint64 public maxLockingDuration;
    uint64 public maxBoost;

    event SetMinLockingDuration(uint64 _minLockingDuration);
    event SetMaxLockingDuration(uint64 _maxLockingDuration);
    event SetMaxBoost(uint64 _maxBoost);

    error InvalidLockingDuration();

    /**
     * @notice initializes the contract state
     * @param _minLockingDuration minimum non-zero locking duration in seconds
     * @param _maxLockingDuration maximum locking duration in seconds
     * @param _maxBoost maximum boost multiplier
     */
    constructor(uint64 _minLockingDuration, uint64 _maxLockingDuration, uint64 _maxBoost) {
        minLockingDuration = _minLockingDuration;
        maxLockingDuration = _maxLockingDuration;
        maxBoost = _maxBoost;
    }

    /**
     * @notice returns the amount of boost balance received for `_amount` of SDL with `_lockingDuration`
     * @dev reverts if `_lockingDuration` exceeds maxLockingDuration
     * @param _amount amount of tokens to lock
     * @param _lockingDuration duration of the locking period
     * @return amount of boost balance received in addition to the unboosted balance
     */
    function getBoostAmount(
        uint256 _amount,
        uint64 _lockingDuration
    ) external view returns (uint256) {
        if (
            (_lockingDuration != 0 && _lockingDuration < minLockingDuration) ||
            _lockingDuration > maxLockingDuration
        ) revert InvalidLockingDuration();
        return
            (_amount * uint256(maxBoost) * uint256(_lockingDuration)) / uint256(maxLockingDuration);
    }

    /**
     * @notice sets the minimum non-zero locking duration
     * @param _minLockingDuration min non-zero locking duration in seconds
     */
    function setMinLockingDuration(uint64 _minLockingDuration) external onlyOwner {
        minLockingDuration = _minLockingDuration;
        emit SetMinLockingDuration(_minLockingDuration);
    }

    /**
     * @notice sets the maximum locking duration
     * @param _maxLockingDuration max locking duration in seconds
     */
    function setMaxLockingDuration(uint64 _maxLockingDuration) external onlyOwner {
        maxLockingDuration = _maxLockingDuration;
        emit SetMaxLockingDuration(_maxLockingDuration);
    }

    /**
     * @notice sets the maximum boost multiplier
     * @dev a multiplier of 1 would mean that a staker's balance is doubled if they lock for the max
     * locking duration
     * @param _maxBoost max boost multiplier
     */
    function setMaxBoost(uint64 _maxBoost) external onlyOwner {
        maxBoost = _maxBoost;
        emit SetMaxBoost(_maxBoost);
    }
}
