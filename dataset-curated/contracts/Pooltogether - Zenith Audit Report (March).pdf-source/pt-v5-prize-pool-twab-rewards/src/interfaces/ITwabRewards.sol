// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  PoolTogether V5 ITwabRewards
 * @author PoolTogether Inc. & G9 Software Inc.
 * @notice TwabRewards contract interface.
 */
interface ITwabRewards {
    /**
     * @notice Claim rewards for a given promotion and epoch.
     * @dev Rewards can be claimed on behalf of a user.
     * @dev Rewards can only be claimed for a past epoch.
     * @param user Address of the user to claim rewards for
     * @param promotionId Id of the promotion to claim rewards for
     * @param epochIds Epoch ids to claim rewards for
     * @return Total amount of rewards claimed
     */
    function claimRewards(address user, uint256 promotionId, uint8[] calldata epochIds) external returns (uint256);
}
