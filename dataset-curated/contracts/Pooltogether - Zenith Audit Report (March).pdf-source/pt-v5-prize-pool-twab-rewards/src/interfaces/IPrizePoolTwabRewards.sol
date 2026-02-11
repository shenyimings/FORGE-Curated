// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @notice Struct to keep track of each promotion's settings.
 * @param token Address of the token to be distributed as reward
 * @param epochDuration Duration of one epoch in draws
 * @param createdAt Timestamp at which the promotion was created
 * @param numberOfEpochs Number of epochs the promotion will last for
 * @param startTimestamp Timestamp at which the promotion starts
 * @param tokensPerEpoch Number of tokens to be distributed per epoch
 * @param rewardsUnclaimed Amount of rewards that have not been claimed yet
 */
struct Promotion {
    IERC20 token;
    uint40 epochDuration;
    uint40 createdAt;
    uint8 numberOfEpochs;
    // first word ends
    uint40 startTimestamp;
    uint104 tokensPerEpoch;
    uint112 rewardsUnclaimed;
    // second word ends
}

/**
 * @title  PoolTogether V5 IPrizePoolTwabRewards
 * @author PoolTogether Inc. & G9 Software Inc.
 * @notice PrizePoolTwabRewards contract interface.
 */
interface IPrizePoolTwabRewards {

    /**
     * @notice Returns the id of the latest created promotion. Will be 0 if no promotions have been created yet.
     * @return Id of the latest created promotion
     */
    function latestPromotionId() external view returns (uint256);

    /**
     * @notice Creates a new promotion.
     * @param token Address of the token to be distributed
     * @param startTimestamp Timestamp at which the promotion starts. MUST be aligned with the Prize Pool's draw start or end times.
     * @param tokensPerEpoch Number of tokens to be distributed per epoch
     * @param epochDuration Duration of one epoch in seconds. 
     * @param numberOfEpochs Number of epochs the promotion will last for
     * @return Id of the newly created promotion
     */
    function createPromotion(
        IERC20 token,
        uint40 startTimestamp,
        uint104 tokensPerEpoch,
        uint40 epochDuration,
        uint8 numberOfEpochs
    ) external returns (uint256);

    /**
     * @notice End currently active promotion and send promotion tokens for remaining epochs back to the creator.
     * @param promotionId Promotion id to end
     * @param to Address that will receive any remaining tokens
     * @return True if operation was successful
     */
    function endPromotion(uint256 promotionId, address to) external returns (bool);

    /**
     * @notice Delete an inactive promotion and sends back any unclaimed tokens to the creator.
     * @dev This function will revert if the promotion is still active.
     * @dev This function will revert if the grace period is not over yet.
     * @param promotionId Promotion id to destroy
     * @param to Address that will receive any remaining tokens
     * @return True if operation was successful
     */
    function destroyPromotion(uint256 promotionId, address to) external returns (bool);

    /**
     * @notice Extend promotion by adding more epochs. The caller must have approved the contract to transfer the tokens (numberOfEpochs * tokensPerEpoch).
     * @param promotionId Id of the promotion to extend
     * @param numberOfEpochs Number of epochs to add
     * @return True if the operation was successful
     */
    function extendPromotion(uint256 promotionId, uint8 numberOfEpochs) external returns (bool);

    /**
     * @notice Claim rewards for a given promotion and epoch.
     * @dev Rewards can be claimed on behalf of a user.
     * @dev Rewards can only be claimed for a past epoch.
     * @param user Address of the user to claim rewards for
     * @param promotionId Id of the promotion to claim rewards for
     * @param epochIds Epoch ids to claim rewards for
     * @return Total amount of rewards claimed
     */
    function claimRewards(address vault, address user, uint256 promotionId, uint8[] calldata epochIds) external returns (uint256);

    /**
     * @notice Claim rewards for all epochs from `_startEpochId` to the most recently ended epoch.
     * @param _vault Address of the vault
     * @param _user Address of the user
     * @param _promotionId Id of the promotion
     * @param _startEpochId Id of the epoch to start claiming rewards from
     * @return Amount of tokens transferred to the recipient address
     */
    function claimRewardedEpochs(address _vault, address _user, uint256 _promotionId, uint8 _startEpochId) external returns (uint256);

    /**
     * @notice Get settings for a specific promotion.
     * @param promotionId Id of the promotion to get settings for
     * @return Promotion settings
     */
    function getPromotion(uint256 promotionId) external view returns (Promotion memory);

    /**
     * @notice Get the current epoch id of a promotion.
     * @param promotionId Id of the promotion to get current epoch for
     * @return Current epoch id of the promotion
     */
    function getEpochIdNow(uint256 promotionId) external view returns (uint8);

    /**
     * @notice Get the epoch id of a promotion given a timestamp
     * @param promotionId Id of the promotion to get current epoch for
     * @param timestamp Timestamp to get the epoch id for
     * @return Current epoch id of the promotion
     */
    function getEpochIdAt(uint256 promotionId, uint256 timestamp) external view returns (uint8);

    /**
     * @notice Get the total amount of tokens left to be rewarded.
     * @param promotionId Id of the promotion to get the total amount of tokens left to be rewarded for
     * @return Amount of tokens left to be rewarded
     */
    function getRemainingRewards(uint256 promotionId) external view returns (uint128);

}
