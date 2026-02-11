// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

interface IRewardDistributorData {
    struct RewardMarketState {
        /// @notice The supply speed for each market
        uint256 supplySpeed;
        /// @notice The supply index for each market
        uint224 supplyIndex;
        /// @notice The last block timestamp that Reward accrued for supply
        uint32 supplyBlock;
        /// @notice The borrow speed for each market
        uint256 borrowSpeed;
        /// @notice The borrow index for each market
        uint224 borrowIndex;
        /// @notice The last block timestamp that Reward accrued for borrow
        uint32 borrowBlock;
    }

    struct RewardAccountState {
        /// @notice The supply index for each market as of the last time the account accrued Reward
        mapping(address => uint256) supplierIndex;
        /// @notice The borrow index for each market as of the last time the account accrued Reward
        mapping(address => uint256) borrowerIndex;
        /// @notice Accrued Reward but not yet transferred
        uint256 rewardAccrued;
    }
}

interface IRewardDistributor {
    event RewardAccrued(address indexed rewardToken, address indexed user, uint256 deltaAccrued, uint256 totalAccrued);

    event RewardGranted(address indexed rewardToken, address indexed user, uint256 amount);

    event SupplySpeedUpdated(address indexed rewardToken, address indexed mToken, uint256 supplySpeed);

    event BorrowSpeedUpdated(address indexed rewardToken, address indexed mToken, uint256 borrowSpeed);

    event OperatorSet(address indexed oldOperator, address indexed newOperator);

    event WhitelistedToken(address indexed token);

    event SupplyIndexNotified(address indexed rewardToken, address indexed mToken);

    event BorrowIndexNotified(address indexed rewardToken, address indexed mToken);

    /**
     * @notice The operator that rewards are distributed to
     */
    function operator() external view returns (address);

    /**
     * @notice Flag to check if reward token added before
     * @param _token the token to check for
     */
    function isRewardToken(address _token) external view returns (bool);

    /**
     * @notice Added reward tokens
     */
    function getRewardTokens() external view returns (address[] memory);

    /**
     * @notice Get block timestamp
     */
    function getBlockTimestamp() external view returns (uint32);

    /**
     * @notice Notifies supply index
     */
    function notifySupplyIndex(address mToken) external;

    /**
     * @notice Notifies borrow index
     */
    function notifyBorrowIndex(address mToken) external;

    /**
     * @notice Notifies supplier
     */
    function notifySupplier(address mToken, address supplier) external;

    /**
     * @notice Notifies borrower
     */
    function notifyBorrower(address mToken, address borrower) external;

    /**
     * @notice Claim tokens for `holders
     * @param holders the accounts to claim for
     */
    function claim(address[] memory holders) external;
}
