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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {ImToken} from "src/interfaces/ImToken.sol";
import {ExponentialNoError} from "src/utils/ExponentialNoError.sol";
import {IRewardDistributor, IRewardDistributorData} from "src/interfaces/IRewardDistributor.sol";

contract RewardDistributor is
    IRewardDistributor,
    ExponentialNoError,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ----------- STORAGE ------------
    uint224 public constant REWARD_INITIAL_INDEX = 1e36;

    /**
     * @inheritdoc IRewardDistributor
     */
    address public operator;

    /**
     * @notice The Reward state for each reward token for each market
     */
    mapping(address => mapping(address => IRewardDistributorData.RewardMarketState)) public rewardMarketState;
    /**
     * @notice The Reward state for each reward token for each account
     */
    mapping(address => mapping(address => IRewardDistributorData.RewardAccountState)) public rewardAccountState;

    /**
     * @notice Added reward tokens
     */
    address[] public rewardTokens;

    /**
     * @inheritdoc IRewardDistributor
     */
    mapping(address => bool) public isRewardToken;

    error RewardDistributor_OnlyOperator();
    error RewardDistributor_TransferFailed();
    error RewardDistributor_RewardNotValid();
    error RewardDistributor_AddressNotValid();
    error RewardDistributor_AddressAlreadyRegistered();
    error RewardDistributor_SupplySpeedArrayLengthMismatch();
    error RewardDistributor_BorrowSpeedArrayLengthMismatch();

    // ----------- MODIFIERS ------------
    modifier onlyOperator() {
        require(msg.sender == operator, RewardDistributor_OnlyOperator());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------- PUBLIC ------------
    function claim(address[] memory holders) public override nonReentrant {
        for (uint256 i = 0; i < rewardTokens.length;) {
            _claim(rewardTokens[i], holders);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IRewardDistributor
     */
    function getBlockTimestamp() public view override returns (uint32) {
        // needs to have a string error message
        return safe32(block.timestamp, "block timestamp exceeds 32 bits");
    }

    /**
     * @inheritdoc IRewardDistributor
     */
    function getRewardTokens() public view override returns (address[] memory) {
        return rewardTokens;
    }

    // ----------- OWNER ------------
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
    }

    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), RewardDistributor_AddressNotValid());
        emit OperatorSet(operator, _operator);
        operator = _operator;
    }

    function whitelistToken(address rewardToken_) public onlyOwner {
        require(rewardToken_ != address(0), RewardDistributor_AddressNotValid());
        require(!isRewardToken[rewardToken_], RewardDistributor_AddressAlreadyRegistered());

        rewardTokens.push(rewardToken_);
        isRewardToken[rewardToken_] = true;

        emit WhitelistedToken(rewardToken_);
    }

    function updateRewardSpeeds(
        address rewardToken_,
        address[] memory mTokens,
        uint256[] memory supplySpeeds,
        uint256[] memory borrowSpeeds
    ) public onlyOwner {
        require(isRewardToken[rewardToken_], RewardDistributor_RewardNotValid());
        require(mTokens.length == supplySpeeds.length, RewardDistributor_SupplySpeedArrayLengthMismatch());
        require(mTokens.length == borrowSpeeds.length, RewardDistributor_BorrowSpeedArrayLengthMismatch());

        for (uint256 i = 0; i < mTokens.length;) {
            _updateRewardSpeed(rewardToken_, mTokens[i], supplySpeeds[i], borrowSpeeds[i]);

            unchecked {
                ++i;
            }
        }
    }

    function grantReward(address token, address user, uint256 amount) public onlyOwner {
        require(isRewardToken[token], RewardDistributor_RewardNotValid());
        _grantReward(token, user, amount);
    }

    // ----------- OPERATOR ------------
    /**
     * @inheritdoc IRewardDistributor
     */
    function notifySupplyIndex(address mToken) external override onlyOperator {
        for (uint256 i = 0; i < rewardTokens.length;) {
            _notifySupplyIndex(rewardTokens[i], mToken);

            emit SupplyIndexNotified(rewardTokens[i], mToken);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IRewardDistributor
     */
    function notifyBorrowIndex(address mToken) external override onlyOperator {
        for (uint256 i = 0; i < rewardTokens.length;) {
            _notifyBorrowIndex(rewardTokens[i], mToken);

            emit BorrowIndexNotified(rewardTokens[i], mToken);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IRewardDistributor
     */
    function notifySupplier(address mToken, address supplier) external override onlyOperator {
        for (uint256 i = 0; i < rewardTokens.length;) {
            _notifySupplier(rewardTokens[i], mToken, supplier);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IRewardDistributor
     */
    function notifyBorrower(address mToken, address borrower) external override onlyOperator {
        for (uint256 i = 0; i < rewardTokens.length;) {
            _notifyBorrower(rewardTokens[i], mToken, borrower);

            unchecked {
                ++i;
            }
        }
    }

    // ----------- PRIVATE ------------
    function _updateRewardSpeed(address rewardToken, address mToken, uint256 supplySpeed, uint256 borrowSpeed)
        private
    {
        IRewardDistributorData.RewardMarketState storage marketState = rewardMarketState[rewardToken][mToken];

        if (marketState.supplySpeed != supplySpeed) {
            if (marketState.supplyIndex == 0) {
                marketState.supplyIndex = REWARD_INITIAL_INDEX;
            }

            _notifySupplyIndex(rewardToken, mToken);
            emit SupplyIndexNotified(rewardToken, mToken);
            marketState.supplySpeed = supplySpeed;
            emit SupplySpeedUpdated(rewardToken, mToken, supplySpeed);
        }

        if (marketState.borrowSpeed != borrowSpeed) {
            if (marketState.borrowIndex == 0) {
                marketState.borrowIndex = REWARD_INITIAL_INDEX;
            }

            _notifyBorrowIndex(rewardToken, mToken);
            emit BorrowIndexNotified(rewardToken, mToken);
            marketState.borrowSpeed = borrowSpeed;
            emit BorrowSpeedUpdated(rewardToken, mToken, borrowSpeed);
        }
    }

    function _notifySupplyIndex(address rewardToken, address mToken) private {
        IRewardDistributorData.RewardMarketState storage marketState = rewardMarketState[rewardToken][mToken];

        uint32 blockTimestamp = getBlockTimestamp();

        if (blockTimestamp > marketState.supplyBlock) {
            if (marketState.supplySpeed > 0) {
                uint256 deltaBlocks = blockTimestamp - marketState.supplyBlock;
                uint256 supplyTokens = ImToken(mToken).totalSupply();
                uint256 accrued = mul_(deltaBlocks, marketState.supplySpeed);
                Double memory ratio = supplyTokens > 0 ? fraction(accrued, supplyTokens) : Double({mantissa: 0});
                marketState.supplyIndex = safe224(
                    add_(Double({mantissa: marketState.supplyIndex}), ratio).mantissa,
                    "new index exceeds 224 bits" // needs to be a string
                );
            }

            marketState.supplyBlock = blockTimestamp;
        }
    }

    function _notifyBorrowIndex(address rewardToken, address mToken) private {
        Exp memory marketBorrowIndex = Exp({mantissa: ImToken(mToken).borrowIndex()});

        IRewardDistributorData.RewardMarketState storage marketState = rewardMarketState[rewardToken][mToken];

        uint32 blockTimestamp = getBlockTimestamp();

        if (blockTimestamp > marketState.borrowBlock) {
            if (marketState.borrowSpeed > 0) {
                uint256 deltaBlocks = blockTimestamp - marketState.borrowBlock;
                uint256 borrowAmount = div_(ImToken(mToken).totalBorrows(), marketBorrowIndex);
                uint256 accrued = mul_(deltaBlocks, marketState.borrowSpeed);
                Double memory ratio = borrowAmount > 0 ? fraction(accrued, borrowAmount) : Double({mantissa: 0});
                marketState.borrowIndex = safe224(
                    add_(Double({mantissa: marketState.borrowIndex}), ratio).mantissa,
                    "new index exceeds 224 bits" // needs to be a string
                );
            }

            marketState.borrowBlock = blockTimestamp;
        }
    }

    function _notifySupplier(address rewardToken, address mToken, address supplier) private {
        IRewardDistributorData.RewardMarketState storage marketState = rewardMarketState[rewardToken][mToken];
        IRewardDistributorData.RewardAccountState storage accountState = rewardAccountState[rewardToken][supplier];

        uint256 supplyIndex = marketState.supplyIndex;
        uint256 supplierIndex = accountState.supplierIndex[mToken];

        // Update supplier's index to the current index since we are distributing accrued Reward
        accountState.supplierIndex[mToken] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= REWARD_INITIAL_INDEX) {
            supplierIndex = REWARD_INITIAL_INDEX;
        }

        // Calculate change in the cumulative sum of the Reward per mToken accrued
        Double memory deltaIndex = Double({mantissa: sub_(supplyIndex, supplierIndex)});

        uint256 supplierTokens = ImToken(mToken).balanceOf(supplier);

        // Calculate Reward accrued: mTokenAmount * accruedPerMToken
        uint256 supplierDelta = mul_(supplierTokens, deltaIndex);

        accountState.rewardAccrued = add_(accountState.rewardAccrued, supplierDelta);

        emit RewardAccrued(rewardToken, supplier, supplierDelta, accountState.rewardAccrued);
    }

    function _notifyBorrower(address rewardToken, address mToken, address borrower) private {
        Exp memory marketBorrowIndex = Exp({mantissa: ImToken(mToken).borrowIndex()});

        IRewardDistributorData.RewardMarketState storage marketState = rewardMarketState[rewardToken][mToken];
        IRewardDistributorData.RewardAccountState storage accountState = rewardAccountState[rewardToken][borrower];

        uint256 borrowIndex = marketState.borrowIndex;
        uint256 borrowerIndex = accountState.borrowerIndex[mToken];

        // Update borrowers's index to the current index since we are distributing accrued Reward
        accountState.borrowerIndex[mToken] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= REWARD_INITIAL_INDEX) {
            // Covers the case where users borrowed tokens before the market's borrow state index was set.
            // Rewards the user with Reward accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = REWARD_INITIAL_INDEX;
        }

        // Calculate change in the cumulative sum of the Reward per borrowed unit accrued
        Double memory deltaIndex = Double({mantissa: sub_(borrowIndex, borrowerIndex)});

        uint256 borrowerAmount = div_(ImToken(mToken).borrowBalanceStored(borrower), marketBorrowIndex);

        // Calculate Reward accrued: mTokenAmount * accruedPerBorrowedUnit
        uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);

        accountState.rewardAccrued = add_(accountState.rewardAccrued, borrowerDelta);

        emit RewardAccrued(rewardToken, borrower, borrowerDelta, accountState.rewardAccrued);
    }

    function _claim(address rewardToken, address[] memory holders) internal {
        for (uint256 j = 0; j < holders.length;) {
            IRewardDistributorData.RewardAccountState storage accountState = rewardAccountState[rewardToken][holders[j]];

            accountState.rewardAccrued = _grantReward(rewardToken, holders[j], accountState.rewardAccrued);

            unchecked {
                ++j;
            }
        }
    }

    function _grantReward(address token, address user, uint256 amount) internal returns (uint256) {
        uint256 remaining = ImToken(token).balanceOf(address(this));
        if (amount > 0 && amount <= remaining) {
            bool status = ImToken(token).transfer(user, amount);
            require(status, RewardDistributor_TransferFailed());

            emit RewardGranted(token, user, amount);

            return 0;
        }
        return amount;
    }
}
