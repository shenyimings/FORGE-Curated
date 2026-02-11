// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "openzeppelin-contracts/utils/math/SafeCast.sol";
import { Multicall } from "openzeppelin-contracts/utils/Multicall.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import { IPrizePool } from "./external/IPrizePool.sol";
import { IPrizePoolTwabRewards, Promotion } from "./interfaces/IPrizePoolTwabRewards.sol";
import { ITwabRewards } from "./interfaces/ITwabRewards.sol";

/* ============ Custom Errors ============ */

/// @notice Thrown when the TwabController address set in the constructor is the zero address.
error TwabControllerZeroAddress();

/// @notice Thrown when a promotion is created with an emission of zero tokens per epoch.
error ZeroTokensPerEpoch();

/// @notice Thrown when the number of epochs is zero when it must be greater than zero.
error ZeroEpochs();

/// @notice Thrown if the tokens received at the creation of a promotion is less than the expected amount.
/// @param received The amount of tokens received
/// @param expected The expected amount of tokens
error TokensReceivedLessThanExpected(uint256 received, uint256 expected);

/// @notice Thrown if the address to receive tokens from ending or destroying a promotion is the zero address.
error PayeeZeroAddress();

/// @notice Thrown if an action cannot be completed while the grace period is active.
/// @param gracePeriodEndTimestamp The end timestamp of the grace period
error GracePeriodActive(uint256 gracePeriodEndTimestamp);

/// @notice Thrown if a promotion extension would exceed the max number of epochs.
/// @param epochExtension The number of epochs to extend the promotion by
/// @param currentEpochs The current number of epochs in the promotion
/// @param maxEpochs The max number of epochs that a promotion can have
error ExceedsMaxEpochs(uint8 epochExtension, uint8 currentEpochs, uint8 maxEpochs);

/// @notice Thrown if rewards for the promotion epoch have already been claimed by the user.
/// @param promotionId The ID of the promotion
/// @param user The address of the user that the rewards are being claimed for
/// @param epochId The epoch that rewards are being claimed from
error RewardsAlreadyClaimed(uint256 promotionId, address user, uint8 epochId);

/// @notice Thrown if a promotion is no longer active.
/// @param promotionId The ID of the promotion
error PromotionInactive(uint256 promotionId);

/// @notice Thrown if the sender is not the promotion creator on a creator-only action.
/// @param sender The address of the sender
/// @param creator The address of the creator
error OnlyPromotionCreator(address sender, address creator);

/// @notice Thrown if the rewards for an epoch are being claimed before the epoch is over.
/// @param epochEndTimestamp The time at which the epoch will end
error EpochNotOver(uint64 epochEndTimestamp);

/// @notice Thrown if an epoch is outside the range of epochs in a promotion.
/// @param epochId The ID of the epoch
/// @param numberOfEpochs The number of epochs in the promotion
error InvalidEpochId(uint8 epochId, uint8 numberOfEpochs);

/// @notice Thrown if the given prize pool address is zero
error PrizePoolZeroAddress();

/// @notice Thrown when the epoch duration is less than the draw period.
error EpochDurationLtDrawPeriod();
    
/// @notice Thrown when the epoch duration is not a multiple of the draw period.
error EpochDurationNotMultipleOfDrawPeriod();
    
/// @notice Thrown when the start time is less than the first draw opens at time.
error StartTimeLtFirstDrawOpensAt();
    
/// @notice Thrown when the start time is not aligned with the draws.
error StartTimeNotAlignedWithDraws();

/// @notice Thrown when there are no epochs available to claim
error NoEpochsToClaim(uint8 startEpochId, uint8 currentEpochId);

/**
 * @title PoolTogether V5 PrizePoolTwabRewards
 * @author G9 Software Inc.
 * @notice Contract to distribute rewards to depositors across all vaults that contribute to a Prize Pool.
 * The contract supports multiple reward "promotions". Each promotion can define a different reward token,
 * start time, epoch duration, and number of epochs. Promotions divide time into evenly sized epochs; and users 
 * can claim rewards for each epoch. The amount each user gets is based on their portion of the Vault twab * vault contribution,
 * where the vault contribution is fraction of prize pool prizes that the vault contributed during the epoch.
 * @dev This contract does not support the use of fee on transfer tokens.
 */
contract PrizePoolTwabRewards is IPrizePoolTwabRewards, Multicall {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /* ============ Global Variables ============ */

    /// @notice TwabController contract from which the promotions read time-weighted average balances from.
    TwabController public immutable twabController;

    /// @notice The Prize Pool used to compute the vault contributions.
    IPrizePool public immutable prizePool;

    /// @notice Cached draw period seconds from the prize pool.
    uint48 internal immutable _drawPeriodSeconds;

    /// @notice Cached first draw opens at timestamp from the prize pool.
    uint48 internal immutable _firstDrawOpensAt;

    /// @notice The special SPONSORSHIP address constant used in the TwabController.
    address constant SPONSORSHIP_ADDRESS = address(1);

    /// @notice Period during which the promotion owner can't destroy a promotion.
    uint32 public constant GRACE_PERIOD = 60 days;

    /// @notice Settings of each promotion.
    mapping(uint256 => Promotion) internal _promotions;

    /// @notice Creator of each promotion
    mapping(uint256 => address) public promotionCreators;

    /**
     * @notice Latest recorded promotion id.
     * @dev Starts at 0 and is incremented by 1 for each new promotion. So the first promotion will have id 1, the second 2, etc.
     */
    uint256 public latestPromotionId;

    /**
     * @notice Keeps track of claimed rewards per user.
     * @dev claimedEpochs[promotionId][user] => claimedEpochs
     * @dev We pack epochs claimed by a user into a uint256. So we can't store more than 256 epochs.
     */
    mapping(uint256 promotionId => mapping(address vault => mapping(address user => bytes32 claimMask))) public claimedEpochs;

    /**
     * @notice Cache of each epoch total contribution amount.
     * @dev Max number of epochs is 256, so limited it appropriately. Prize Pool draw contributions are stored as uint160, but 128 bits should give us plenty of overhead.
     */
    mapping(uint256 promotionId => EpochCache[256]) internal _epochCaches;

    /**
     * @notice Cache of each vault's epoch total supply and contribution to the prize pool.
     * @dev Max number of epochs is 256, so limited it appropriately. Twab Controller supply limit is 96bits, so we can store it in a uint96.
     */
    mapping(uint256 promotionId => mapping(address vault => VaultEpochCache[256])) internal _vaultEpochCaches;

    struct EpochCache {
        uint128 totalContributed;
    }

    struct VaultEpochCache {
        uint128 totalSupply;
        uint128 contributed;
    }

    /* ============ Events ============ */

    /**
     * @notice Emitted when a promotion is created.
     * @param promotionId Id of the newly created promotion
     * @param token The token that will be rewarded from the promotion
     * @param startTimestamp The timestamp at which the promotion starts
     * @param tokensPerEpoch The number of tokens emitted per epoch
     * @param epochDuration The duration of epoch in seconds
     * @param initialNumberOfEpochs The initial number of epochs the promotion is set to run for
     */
    event PromotionCreated(
        uint256 indexed promotionId,
        IERC20 indexed token,
        uint40 startTimestamp,
        uint104 tokensPerEpoch,
        uint40 epochDuration,
        uint8 initialNumberOfEpochs
    );

    /**
     * @notice Emitted when a promotion is ended.
     * @param promotionId Id of the promotion being ended
     * @param recipient Address of the recipient that will receive the remaining rewards
     * @param amount Amount of tokens transferred to the recipient
     * @param epochNumber Epoch number at which the promotion ended
     */
    event PromotionEnded(uint256 indexed promotionId, address indexed recipient, uint256 amount, uint8 epochNumber);

    /**
     * @notice Emitted when a promotion is destroyed.
     * @param promotionId Id of the promotion being destroyed
     * @param recipient Address of the recipient that will receive the unclaimed rewards
     * @param amount Amount of tokens transferred to the recipient
     */
    event PromotionDestroyed(uint256 indexed promotionId, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a promotion is extended.
     * @param promotionId Id of the promotion being extended
     * @param numberOfEpochs Number of epochs the promotion has been extended by
     */
    event PromotionExtended(uint256 indexed promotionId, uint256 numberOfEpochs);

    /**
     * @notice Emitted when rewards have been claimed.
     * @param promotionId Id of the promotion for which epoch rewards were claimed
     * @param epochClaimFlags Word representing which epochs were claimed
     * @param user Address of the user for which the rewards were claimed
     * @param amount Amount of tokens transferred to the recipient address
     */
    event RewardsClaimed(uint256 indexed promotionId, bytes32 epochClaimFlags, address indexed vault, address indexed user, uint256 amount);

    /* ============ Constructor ============ */

    /**
     * @notice Constructor of the contract.
     * @param _twabController The TwabController contract to reference for vault balance and supply
     * @param _prizePool The PrizePool contract to use for prize contributions
     */
    constructor(TwabController _twabController, IPrizePool _prizePool) {
        if (address(0) == address(_twabController)) revert TwabControllerZeroAddress();
        if (address(0) == address(_prizePool)) revert PrizePoolZeroAddress();
        twabController = _twabController;
        prizePool = _prizePool;
        _drawPeriodSeconds = prizePool.drawPeriodSeconds();
        _firstDrawOpensAt = prizePool.firstDrawOpensAt();
    }

    /* ============ External Functions ============ */

    /**
     * @inheritdoc IPrizePoolTwabRewards
     * @dev For sake of simplicity, `msg.sender` will be the creator of the promotion.
     * @dev `_latestPromotionId` starts at 0 and is incremented by 1 for each new promotion.
     * So the first promotion will have id 1, the second 2, etc.
     * @dev The transaction will revert if the amount of reward tokens provided is not equal to `_tokensPerEpoch * _numberOfEpochs`.
     * This scenario could happen if the token supplied is a fee on transfer one.
     */
    function createPromotion(
        IERC20 _token,
        uint40 _startTimestamp,
        uint104 _tokensPerEpoch,
        uint40 _epochDuration,
        uint8 _numberOfEpochs
    ) external override returns (uint256) {
        if (_tokensPerEpoch == 0) revert ZeroTokensPerEpoch();
        _requireNumberOfEpochs(_numberOfEpochs);
        if (_epochDuration < _drawPeriodSeconds) revert EpochDurationLtDrawPeriod();
        if (_epochDuration % _drawPeriodSeconds != 0) revert EpochDurationNotMultipleOfDrawPeriod();
        if (_startTimestamp < _firstDrawOpensAt) revert StartTimeLtFirstDrawOpensAt();
        if ((_startTimestamp - _firstDrawOpensAt) % _drawPeriodSeconds != 0) revert StartTimeNotAlignedWithDraws();

        // ensure that this contract isn't eligible to win any prizes
        if (twabController.delegateOf(address(_token), address(this)) != SPONSORSHIP_ADDRESS) {
            twabController.delegate(address(_token), SPONSORSHIP_ADDRESS);
        }

        uint256 _nextPromotionId = latestPromotionId + 1;
        latestPromotionId = _nextPromotionId;

        uint112 unclaimedRewards = SafeCast.toUint112(uint(_tokensPerEpoch) * uint(_numberOfEpochs));

        promotionCreators[_nextPromotionId] = msg.sender;
        _promotions[_nextPromotionId] = Promotion({
            startTimestamp: _startTimestamp,
            numberOfEpochs: _numberOfEpochs,
            epochDuration: _epochDuration,
            createdAt: SafeCast.toUint40(block.timestamp),
            token: _token,
            tokensPerEpoch: _tokensPerEpoch,
            rewardsUnclaimed: unclaimedRewards
        });

        uint256 _beforeBalance = _token.balanceOf(address(this));

        _token.safeTransferFrom(msg.sender, address(this), unclaimedRewards);

        uint256 _afterBalance = _token.balanceOf(address(this));

        if (_afterBalance < _beforeBalance + unclaimedRewards)
            revert TokensReceivedLessThanExpected(_afterBalance - _beforeBalance, unclaimedRewards);

        emit PromotionCreated(
            _nextPromotionId,
            _token,
            _startTimestamp,
            _tokensPerEpoch,
            _epochDuration,
            _numberOfEpochs
        );

        return _nextPromotionId;
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function endPromotion(uint256 _promotionId, address _to) external override returns (bool) {
        if (address(0) == _to) revert PayeeZeroAddress();

        Promotion memory _promotion = _getPromotion(_promotionId);
        _requirePromotionCreator(promotionCreators[_promotionId]);
        _requirePromotionActive(_promotionId, _promotion);

        uint8 _epochNumber = _getEpochIdNow(_promotion.startTimestamp, _promotion.epochDuration);
        _promotions[_promotionId].numberOfEpochs = _epochNumber;

        uint112 _remainingRewards = _getRemainingRewards(_promotion);
        _promotions[_promotionId].rewardsUnclaimed = _promotion.rewardsUnclaimed - _remainingRewards;

        _promotion.token.safeTransfer(_to, _remainingRewards);

        emit PromotionEnded(_promotionId, _to, _remainingRewards, _epochNumber);

        return true;
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function destroyPromotion(uint256 _promotionId, address _to) external override returns (bool) {
        if (address(0) == _to) revert PayeeZeroAddress();

        Promotion memory _promotion = _getPromotion(_promotionId);
        _requirePromotionCreator(promotionCreators[_promotionId]);

        uint256 _promotionEndTimestamp = _getPromotionEndTimestamp(_promotion);
        uint256 _promotionCreatedAt = _promotion.createdAt;

        uint256 _gracePeriodEndTimestamp = (
            _promotionEndTimestamp < _promotionCreatedAt ? _promotionCreatedAt : _promotionEndTimestamp
        ) + GRACE_PERIOD;

        if (block.timestamp < _gracePeriodEndTimestamp) revert GracePeriodActive(_gracePeriodEndTimestamp);

        uint256 _rewardsUnclaimed = _promotion.rewardsUnclaimed;
        delete _promotions[_promotionId];

        _promotion.token.safeTransfer(_to, _rewardsUnclaimed);

        emit PromotionDestroyed(_promotionId, _to, _rewardsUnclaimed);

        return true;
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function extendPromotion(uint256 _promotionId, uint8 _numberOfEpochs) external override returns (bool) {
        _requireNumberOfEpochs(_numberOfEpochs);

        Promotion memory _promotion = _getPromotion(_promotionId);
        _requirePromotionActive(_promotionId, _promotion);

        uint8 _currentNumberOfEpochs = _promotion.numberOfEpochs;

        if (_numberOfEpochs > (type(uint8).max - _currentNumberOfEpochs))
            revert ExceedsMaxEpochs(_numberOfEpochs, _currentNumberOfEpochs, type(uint8).max);

        _promotions[_promotionId].numberOfEpochs = _currentNumberOfEpochs + _numberOfEpochs;

        uint112 _amount = SafeCast.toUint112(uint(_numberOfEpochs) * uint(_promotion.tokensPerEpoch));

        _promotions[_promotionId].rewardsUnclaimed = _promotion.rewardsUnclaimed + _amount;
        _promotion.token.safeTransferFrom(msg.sender, address(this), _amount);

        emit PromotionExtended(_promotionId, _numberOfEpochs);

        return true;
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function claimRewards(
        address _vault,
        address _user,
        uint256 _promotionId,
        uint8[] calldata _epochIds
    ) external override returns (uint256) {
        bytes32 _epochClaimFlags = epochIdArrayToBytes(_epochIds);
        return _claimRewards(_vault, _user, _promotionId, _epochClaimFlags, 0);
    }

    /**
     * @notice Pass through to claim regular Twab Rewards. This is intended to allow single tx claiming by EOAs using the built-in Multicall
     * @param _twabRewards TwabRewards contract to claim rewards from
     * @param _user User to claim rewards for
     * @param _promotionId Promotion to claim rewards for
     * @param _epochIds Epoch ids to claim rewards for
     * @return Total amount of rewards claimed
     */
    function claimTwabRewards(
        ITwabRewards _twabRewards, address _user, uint256 _promotionId, uint8[] calldata _epochIds
    ) external returns (uint256) {
        return _twabRewards.claimRewards(_user, _promotionId, _epochIds);
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function claimRewardedEpochs(
        address _vault,
        address _user,
        uint256 _promotionId,
        uint8 _startEpochId
    ) public returns (uint256) {
        bytes32 _epochClaimFlags;
        uint8 endEpochId = getEpochIdNow(_promotionId);
        if (!(endEpochId > _startEpochId)) revert NoEpochsToClaim(_startEpochId, endEpochId);
        for (uint8 index = _startEpochId; index < endEpochId; index++) {
            _epochClaimFlags = _updateClaimedEpoch(_epochClaimFlags, index);
        }
        bytes32 _userClaimedEpochs = claimedEpochs[_promotionId][_vault][_user];
        // exclude epochs already claimed by the user
        _epochClaimFlags = _epochClaimFlags & ~_userClaimedEpochs;
        return _claimRewards(_vault, _user, _promotionId, _epochClaimFlags, _startEpochId);
    }

    /**
     * @notice Calculate rewards for a given vault, user, promotion and epoch ids.
     * @param _vault Vault to calculate rewards for
     * @param _user User to calculate rewards for
     * @param _promotionId Promotion to calculate rewards for
     * @param _epochIds Epoch ids to calculate rewards for
     * @return rewards Array of reward amounts for each epoch
     */
    function calculateRewards(
        address _vault,
        address _user,
        uint256 _promotionId,
        uint8[] calldata _epochIds
    ) external returns (uint256[] memory rewards) {
        rewards = new uint256[](_epochIds.length);
        Promotion memory promotion = _getPromotion(_promotionId);
        for (uint256 index = 0; index < _epochIds.length; ++index) {
            rewards[index] = _calculateRewardAmount(_vault, _user, _promotionId, promotion, _epochIds[index]);
        }
    }

    /**
     * @notice Get reward amount for a given vault
     * @dev Rewards can only be calculated once the epoch is over.
     * @dev Will revert if `_epochId` is not in the past.
     * @param _vault Vault to get reward amount for
     * @param _promotionId Promotion from which the epoch is
     * @param _epochId Epoch id to get reward amount for
     * @return Reward amount
     */
    function getVaultRewardAmount(
        address _vault,
        uint256 _promotionId,
        uint8 _epochId
    ) public returns (uint128) {
        Promotion memory promotion = _getPromotion(_promotionId);
        (
            uint48 _epochStartTimestamp,
            uint48 _epochEndTimestamp,
            uint24 _epochStartDrawId,
            uint24 _epochEndDrawId
        ) = epochRanges(promotion.startTimestamp, promotion.epochDuration, _epochId);
        VaultEpochCache memory vaultEpochCache = _getVaultEpochCache(_promotionId, _epochId, _vault, _epochStartTimestamp, _epochEndTimestamp, _epochStartDrawId, _epochEndDrawId);
        if (vaultEpochCache.contributed == 0) {
            return 0;
        }
        EpochCache memory epochCache = _getEpochCache(_promotionId, _epochId, _epochStartDrawId, _epochEndDrawId);
        uint256 numerator = uint256(promotion.tokensPerEpoch) * uint256(vaultEpochCache.contributed);
        uint256 denominator = uint256(epochCache.totalContributed);
        return SafeCast.toUint128(numerator / denominator);
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function getPromotion(uint256 _promotionId) external view override returns (Promotion memory) {
        return _getPromotion(_promotionId);
    }

    /// @inheritdoc IPrizePoolTwabRewards
    /// @dev Epoch ids and their boolean values are tightly packed and stored in a uint256, so epoch id starts at 0.
    function getEpochIdNow(uint256 _promotionId) public view override returns (uint8) {
        Promotion memory _promotion = _getPromotion(_promotionId);
        return _getEpochIdNow(_promotion.startTimestamp, _promotion.epochDuration);
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function getEpochIdAt(uint256 _promotionId, uint256 _timestamp) public view override returns (uint8) {
        Promotion memory _promotion = _getPromotion(_promotionId);
        return _getEpochIdAt(_promotion.startTimestamp, _promotion.epochDuration, _timestamp);
    }

    /// @inheritdoc IPrizePoolTwabRewards
    function getRemainingRewards(uint256 _promotionId) external view override returns (uint128) {
        return _getRemainingRewards(_getPromotion(_promotionId));
    }

    /**
     * @notice Calculate the draw id at a specific timestamp. Draw ids start at 1.
     * @param _timestamp Timestamp to calculate the draw id at
     * @return Draw id
     */
    function calculateDrawIdAt(uint64 _timestamp) public view returns (uint24) {
        // NOTE: Prize Pool draw ids start at 1; that's why we have to add one below.
        if (_timestamp < _firstDrawOpensAt) return 0;
        else return uint24((_timestamp - _firstDrawOpensAt) / _drawPeriodSeconds) + 1;
    }

    /**
     * @notice Get the time and draw ranges for an epoch
     * @param _promotionId Id of the promotion
     * @param _epochId Id of the epoch to get the ranges for
     * @return epochStartTimestamp Start timestamp of the epoch
     * @return epochEndTimestamp End timestamp of the epoch
     * @return epochStartDrawId Start draw id of the epoch
     * @return epochEndDrawId End draw id of the epoch
     */
    function epochRangesForPromotion(
        uint256 _promotionId,
        uint8 _epochId
    ) public view returns (
        uint48 epochStartTimestamp,
        uint48 epochEndTimestamp,
        uint24 epochStartDrawId,
        uint24 epochEndDrawId
    ) {
        Promotion memory promotion = _promotions[_promotionId];
        return epochRanges(promotion.startTimestamp, promotion.epochDuration, _epochId);
    }

    /**
     * @notice Get the time and draw ranges for an epoch
     * @param _promotionStartTimestamp Start timestamp of the promotion
     * @param _promotionEpochDuration Duration of an epoch in the promotion
     * @param _epochId Id of the epoch to get the ranges for
     * @return epochStartTimestamp Start timestamp of the epoch
     * @return epochEndTimestamp End timestamp of the epoch
     * @return epochStartDrawId Start draw id of the epoch
     * @return epochEndDrawId End draw id of the epoch
     */
    function epochRanges(
        uint48 _promotionStartTimestamp,
        uint48 _promotionEpochDuration,
        uint8 _epochId
    ) public view returns (
        uint48 epochStartTimestamp,
        uint48 epochEndTimestamp,
        uint24 epochStartDrawId,
        uint24 epochEndDrawId
    ) {
        epochStartTimestamp = _promotionStartTimestamp + (_promotionEpochDuration * _epochId);
        epochEndTimestamp = epochStartTimestamp + _promotionEpochDuration;
        epochStartDrawId = calculateDrawIdAt(epochStartTimestamp);
        epochEndDrawId = epochStartDrawId + uint24(_promotionEpochDuration / _drawPeriodSeconds) - 1;
    }

    /**
     * @notice Convert an array of epoch ids to a bytes32 word.
     * @param _epochIds Array of epoch ids to convert
     * @return Tightly Word where each bit represents an epoch
     */
    function epochIdArrayToBytes(uint8[] calldata _epochIds) public pure returns (bytes32) {
        bytes32 _epochClaimFlags;
        for (uint256 index = 0; index < _epochIds.length; ++index) {
            _epochClaimFlags = _updateClaimedEpoch(_epochClaimFlags, _epochIds[index]);
        }
        return _epochClaimFlags;
    }

    /**
     * @notice Converts a bytes32 to an array of epoch ids
     * @param _epochClaimFlags Word where each bit represents an epoch
     * @return Array of epoch ids
     */
    function epochBytesToIdArray(bytes32 _epochClaimFlags) public pure returns (uint8[] memory) {
        uint8 count;
        for (uint256 epoch = 0; epoch < 256; ++epoch) {
            if (_isClaimedEpoch(_epochClaimFlags, uint8(epoch))) {
                ++count;
            }
        }
        uint8[] memory _epochIds = new uint8[](count);
        uint8 idsIndex = 0;
        for (uint256 epoch = 0; epoch < 256; ++epoch) {
            if (_isClaimedEpoch(_epochClaimFlags, uint8(epoch))) {
                _epochIds[idsIndex++] = uint8(epoch);
            }
        }
        return _epochIds;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Claim rewards for a given promotion and epoch.
     * @param _vault Address of the vault
     * @param _user Address of the user
     * @param _promotionId Id of the promotion
     * @param _epochClaimFlags Word representing which epochs were claimed
     * @param startEpochId Id of the epoch to start claiming rewards from
     * @return Amount of tokens transferred to the recipient address
     */
    function _claimRewards(
        address _vault,
        address _user,
        uint256 _promotionId,
        bytes32 _epochClaimFlags,
        uint8 startEpochId
    ) internal returns (uint256) {
        Promotion memory _promotion = _promotions[_promotionId];
        uint256 _rewardsAmount;
        bytes32 _userClaimedEpochs = claimedEpochs[_promotionId][_vault][_user];

        for (uint256 index = startEpochId; index < 256; ++index) {
            if (!_isClaimedEpoch(_epochClaimFlags, uint8(index))) {
                continue;
            }
            if (_isClaimedEpoch(_userClaimedEpochs, uint8(index)))
                revert RewardsAlreadyClaimed(_promotionId, _user, uint8(index));
            _rewardsAmount += _calculateRewardAmount(_vault, _user, _promotionId, _promotion, uint8(index));
            _userClaimedEpochs = _updateClaimedEpoch(_userClaimedEpochs, uint8(index));
        }

        claimedEpochs[_promotionId][_vault][_user] = _userClaimedEpochs;

        _promotions[_promotionId].rewardsUnclaimed = SafeCast.toUint112(uint(_promotion.rewardsUnclaimed) - uint(_rewardsAmount));

        _promotion.token.safeTransfer(_user, _rewardsAmount);

        emit RewardsClaimed(_promotionId, _epochClaimFlags, _vault, _user, _rewardsAmount);

        return _rewardsAmount;
    }

    /**
     * @notice Allow a promotion to be created or extended only by a positive number of epochs.
     * @param _numberOfEpochs Number of epochs to check
     */
    function _requireNumberOfEpochs(uint8 _numberOfEpochs) internal pure {
        if (0 == _numberOfEpochs) revert ZeroEpochs();
    }

    /**
     * @notice Requires that a promotion is active.
     * @param _promotion Promotion to check
     */
    function _requirePromotionActive(uint256 _promotionId, Promotion memory _promotion) internal view {
        if (_getPromotionEndTimestamp(_promotion) <= block.timestamp) revert PromotionInactive(_promotionId);
    }

    /**
     * @notice Requires that msg.sender is the promotion creator.
     * @param creator Creator of the promotion
     */
    function _requirePromotionCreator(address creator) internal view {
        if (msg.sender != creator) revert OnlyPromotionCreator(msg.sender, creator);
    }

    /**
     * @notice Get settings for a specific promotion.
     * @dev Will revert if the promotion does not exist.
     * @param _promotionId Promotion id to get settings for
     * @return Promotion settings
     */
    function _getPromotion(uint256 _promotionId) internal view returns (Promotion memory) {
        Promotion memory _promotion = _promotions[_promotionId];
        return _promotion;
    }

    /**
     * @notice Compute promotion end timestamp.
     * @param _promotion Promotion to compute end timestamp for
     * @return Promotion end timestamp
     */
    function _getPromotionEndTimestamp(Promotion memory _promotion) internal pure returns (uint256) {
        unchecked {
            return _promotion.startTimestamp + (_promotion.epochDuration * _promotion.numberOfEpochs);
        }
    }

    /**
     * @notice Get the current epoch id of a promotion.
     * @dev Epoch ids and their boolean values are tightly packed and stored in a uint256, so epoch id starts at 0.
     * @dev We return the current epoch id if the promotion has not ended.
     * If the current timestamp is before the promotion start timestamp, we return 0.
     * Otherwise, we return the epoch id at the current timestamp. This could be greater than the number of epochs of the promotion.
     * @param _promotionStartTimestamp Start timestamp of the promotion
     * @param _promotionEpochDuration Duration of an epoch for the promotion
     * @return Epoch id
     */
    function _getEpochIdNow(uint256 _promotionStartTimestamp, uint256 _promotionEpochDuration) internal view returns (uint8) {
        return _getEpochIdAt(_promotionStartTimestamp, _promotionEpochDuration, block.timestamp);
    }

    /**
     * @notice Get the epoch id at a specific timestamp.
     * @param _promotionStartTimestamp Start timestamp of the promotion
     * @param _promotionEpochDuration Duration of an epoch for the promotion
     * @param _timestamp Timestamp to get the epoch id for
     */
    function _getEpochIdAt(uint256 _promotionStartTimestamp, uint256 _promotionEpochDuration, uint256 _timestamp) internal pure returns (uint8) {
        uint256 _currentEpochId;

        if (_timestamp > _promotionStartTimestamp) {
            unchecked {
                _currentEpochId = (_timestamp - _promotionStartTimestamp) / _promotionEpochDuration;
            }
        }

        return _currentEpochId > type(uint8).max ? type(uint8).max : uint8(_currentEpochId);
    }

    /**
     * @notice Get reward amount for a specific user.
     * @dev Rewards can only be calculated once the epoch is over.
     * @dev Will revert if `_epochId` is not in the past.
     * @dev Will return 0 if the user average balance in the vault is 0.
     * @param _vault Vault to get reward amount for
     * @param _user User to get reward amount for
     * @param _promotion Promotion from which the epoch is
     * @param _epochId Epoch id to get reward amount for
     * @return Reward amount
     */
    function _calculateRewardAmount(
        address _vault,
        address _user,
        uint256 _promotionId,
        Promotion memory _promotion,
        uint8 _epochId
    ) internal returns (uint256) {
        (
            uint48 _epochStartTimestamp,
            uint48 _epochEndTimestamp,
            uint24 _epochStartDrawId,
            uint24 _epochEndDrawId
        ) = epochRanges(_promotion.startTimestamp, _promotion.epochDuration, _epochId);
        if (block.timestamp < _epochEndTimestamp) revert EpochNotOver(_epochEndTimestamp);
        if (_epochId >= _promotion.numberOfEpochs) revert InvalidEpochId(_epochId, _promotion.numberOfEpochs);
        uint256 _userAverage = twabController.getTwabBetween(
            _vault,
            _user,
            _epochStartTimestamp,
            _epochEndTimestamp
        );

        if (_userAverage > 0) {
            VaultEpochCache memory vaultEpochCache = _getVaultEpochCache(_promotionId, _epochId, _vault, _epochStartTimestamp, _epochEndTimestamp, _epochStartDrawId, _epochEndDrawId);

            if (vaultEpochCache.contributed == 0) {
                return 0;
            }

            EpochCache memory epochCache = _getEpochCache(_promotionId, _epochId, _epochStartDrawId, _epochEndDrawId);

            uint numerator = ((_promotion.tokensPerEpoch * _userAverage) / uint256(vaultEpochCache.totalSupply)) * uint256(vaultEpochCache.contributed);
            uint denominator = (uint256(epochCache.totalContributed));
            return numerator / denominator;
        }
        return 0;
    }

    /**
     * @notice Retrieve the contributed amount for the vault, and the vaults total supply for the given epoch
     * @param _promotionId Promotion id
     * @param _epochId Epoch id
     * @param _vault Vault address
     * @param _epochStartTimestamp Start timestamp of the epoch
     * @param _epochEndTimestamp End timestamp of the epoch
     * @param _epochStartDrawId Start draw id of the epoch
     * @param _epochEndDrawId End draw id of the epoch
     * @return vaultEpochCache VaultEpochCache struct
     */
    function _getVaultEpochCache(
        uint256 _promotionId,
        uint8 _epochId,
        address _vault,
        uint48 _epochStartTimestamp,
        uint48 _epochEndTimestamp,
        uint24 _epochStartDrawId,
        uint24 _epochEndDrawId
    ) internal returns (VaultEpochCache memory vaultEpochCache) {
        vaultEpochCache = _vaultEpochCaches[_promotionId][_vault][_epochId];
        if (vaultEpochCache.contributed == 0) {
            vaultEpochCache.contributed = SafeCast.toUint128(prizePool.getContributedBetween(_vault, _epochStartDrawId, _epochEndDrawId));
            vaultEpochCache.totalSupply = SafeCast.toUint128(twabController.getTotalSupplyTwabBetween(
                _vault,
                _epochStartTimestamp,
                _epochEndTimestamp
            ));
            _vaultEpochCaches[_promotionId][_vault][_epochId] = vaultEpochCache;
        }
    }

    /**
     * @notice Retrieve the total contributed amount for the epoch
     * @param _promotionId Promotion id
     * @param _epochId Epoch id
     * @param _epochStartDrawId Start draw id of the epoch
     * @param _epochEndDrawId End draw id of the epoch
     * @return epochCache EpochCache struct
     */
    function _getEpochCache(
        uint256 _promotionId,
        uint8 _epochId,
        uint24 _epochStartDrawId,
        uint24 _epochEndDrawId
    ) internal returns (EpochCache memory epochCache) {
        epochCache = _epochCaches[_promotionId][_epochId];
        if (epochCache.totalContributed == 0) {
            epochCache.totalContributed = SafeCast.toUint128(prizePool.getTotalContributedBetween(_epochStartDrawId, _epochEndDrawId));
            _epochCaches[_promotionId][_epochId] = epochCache;
        }
    }

    /**
     * @notice Get the total amount of tokens left to be rewarded.
     * @param _promotion Promotion to get the total amount of tokens left to be rewarded for
     * @return Amount of tokens left to be rewarded
     */
    function _getRemainingRewards(Promotion memory _promotion) internal view returns (uint112) {
        if (block.timestamp >= _getPromotionEndTimestamp(_promotion)) {
            return 0;
        }

        return _promotion.tokensPerEpoch * (_promotion.numberOfEpochs - _getEpochIdNow(_promotion.startTimestamp, _promotion.epochDuration));
    }

    /**
    * @notice Set boolean value for a specific epoch.
    * @dev Bits are stored in a uint256 from right to left.
        Let's take the example of the following 8 bits word. 0110 0011
        To set the boolean value to 1 for the epoch id 2, we need to create a mask by shifting 1 to the left by 2 bits.
        We get: 0000 0001 << 2 = 0000 0100
        We then OR the mask with the word to set the value.
        We get: 0110 0011 | 0000 0100 = 0110 0111
    * @param _userClaimedEpochs Tightly packed epoch ids with their boolean values
    * @param _epochId Id of the epoch to set the boolean for
    * @return Tightly packed epoch ids with the newly boolean value set
    */
    function _updateClaimedEpoch(bytes32 _userClaimedEpochs, uint8 _epochId) internal pure returns (bytes32) {
        return _userClaimedEpochs | (bytes32(uint256(1)) << _epochId);
    }

    /**
    * @notice Check if rewards of an epoch for a given promotion have already been claimed by the user.
    * @dev Bits are stored in a uint256 from right to left.
        Let's take the example of the following 8 bits word. 0110 0111
        To retrieve the boolean value for the epoch id 2, we need to shift the word to the right by 2 bits.
        We get: 0110 0111 >> 2 = 0001 1001
        We then get the value of the last bit by masking with 1.
        We get: 0001 1001 & 0000 0001 = 0000 0001 = 1
        We then return the boolean value true since the last bit is 1.
    * @param _userClaimedEpochs Record of epochs already claimed by the user
    * @param _epochId Epoch id to check
    * @return true if the rewards have already been claimed for the given epoch, false otherwise
     */
    function _isClaimedEpoch(bytes32 _userClaimedEpochs, uint8 _epochId) internal pure returns (bool) {
        bool value = (uint256(_userClaimedEpochs) >> _epochId) & uint256(1) == 1;
        return value;
    }
}
