// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Foundation <security@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IConvexCvxLockerV2 Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IConvexCvxLockerV2 {
    struct LockedBalance {
        uint112 amount;
        uint112 boosted;
        uint32 unlockTime;
    }

    function checkpointEpoch() external;

    function lockDuration() external view returns (uint256 duration_);

    function lockedBalances(address _account)
        external
        view
        returns (uint256 total_, uint256 unlockable_, uint256 locked_, LockedBalance[] memory lockData_);

    function epochCount() external view returns (uint256 count_);

    function rewardsDuration() external view returns (uint256 duration_);

    function rewardTokens(uint256 _rewardId) external view returns (address rewardToken_);

    function rewardData(address _rewardToken)
        external
        view
        returns (
            bool useBoost_,
            uint40 periodFinish_,
            uint208 rewardRate_,
            uint40 lastUpdateTime_,
            uint208 rewardPerTokenStored_
        );
}
