// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RewardMerkleDistributor
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.org
/// @notice Contract to distribute rewards using a merkle tree.
contract RewardMerkleDistributor is AccessManaged, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //-------------------------------------------
    // Storage
    //-------------------------------------------

    struct MerkleDrop {
        bytes32 root;
        uint256 totalAmount;
        uint64 startTime;
        uint64 expiryTime;
    }

    struct ClaimCallData {
        uint64 epochId;
        address account;
        uint256 amount;
        bytes32[] merkleProof;
    }

    /// @dev The length of a claim/allocate epoch
    uint64 public constant EPOCH_LENGTH = 28 days;
    /// @notice The token to distribute.
    IERC20 public immutable TOKEN;
    /// @notice address that will received unclaimed token after epoch' expired time.
    address public expiredRewardsRecipient;
    /// @notice The total amount of tokens claimed.
    uint256 public totalClaimed;
    /// @notice The merkle drops.
    mapping(uint64 epochId => MerkleDrop merkleDrop) public merkleDrops;
    /// @notice The rewards already claimed.
    mapping(address account => mapping(uint64 epochId => bool hasClaimed)) public hasClaimed;
    /// @notice Tracks total amount of user claimed amounts.
    mapping(address account => uint256 totalClaimed) public totalClaimedPerUser;
    /// @notice Maps total claimed amount per epoch.
    mapping(uint64 epochId => uint256 totalClaimed) public totalClaimedPerEpoch;

    //-------------------------------------------
    // Events
    //-------------------------------------------

    /// @notice Emitted when the root is updated.
    /// @param epochId The epoch id.
    /// @param root The merkle's tree root.
    /// @param totalAmount The totalAmount to distribute.
    /// @param startTime The start time of the epoch.
    /// @param endTime The time at which all none claimed token will be send to the expiredRewardsRecipient address.
    event MerkleDropUpdated(uint64 epochId, bytes32 root, uint256 totalAmount, uint64 startTime, uint64 endTime);

    /// @notice Emitted when tokens are rescued.
    /// @param token The address of the token.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens rescued.
    event EmergencyRescued(address token, address to, uint256 amount);

    /// @notice Emitted when an account claims rewards.
    /// @param epochId The epochId claimed.
    /// @param account The address of the claimer.
    /// @param amount The amount of rewards claimed.
    event RewardsClaimed(uint64 epochId, address account, uint256 amount);

    /// @notice Emitted when expired rewards are forwarded.
    /// @param epochId The epochId forwarded.
    /// @param amount The amount of rewards forwarded.
    event ExpiredRewardsForwarded(uint64 epochId, uint256 amount);

    /// @notice Emitted when the expired rewards recipient is updated.
    /// @param _newExpiredRewardsRecipient The new expired rewards recipient.
    event ExpiredRewardsRecipientUpdated(address _newExpiredRewardsRecipient);

    //-------------------------------------------
    // Errors
    //-------------------------------------------
    /// @notice Thrown when the address == address(0).
    error AddressZero();
    /// @notice Thrown when the proof is invalid or expired.
    error ProofInvalid();
    /// @notice Thrown when the claimer has already claimed the rewards.
    error AlreadyClaimed();
    /// @notice Thrown when epoch expired.
    error EpochExpired();
    /// @notice Thrown when epoch didn't expired.
    error EpochNotExpired();
    /// @notice Thrown when claim windows didn't not start.
    error NotStarted();
    /// @notice Thrown when totalAmountClaimed for the epoch after a claim will exceed the total amount to distribute.
    error TotalEpochRewardsExceeded();
    /// @notice Thrown when the epochIds array is empty.
    error EmptyArray();

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @notice Constructs RewardsDistributor contract.
    /// @param _accessManager The address of the AccessManager.
    /// @param _token The address of the token to distribute.
    /// @param _expiredRewardsRecipient The address of the recipient of the expired rewards.
    constructor(
        address _accessManager,
        address _token,
        address _expiredRewardsRecipient
    )
        AccessManaged(_accessManager)
    {
        if (_expiredRewardsRecipient == address(0)) revert AddressZero();
        TOKEN = IERC20(_token);
        expiredRewardsRecipient = _expiredRewardsRecipient;
    }

    //-------------------------------------------
    // External Functions
    //-------------------------------------------

    /// @notice Claims rewards for multi Epoch.
    /// @param _claimsData The claim data array info.
    function claims(ClaimCallData[] calldata _claimsData) external whenNotPaused nonReentrant {
        uint256 len = _claimsData.length;
        if (len == 0) revert EmptyArray();
        uint256 i;
        for (; i < len; ++i) {
            _claim(_claimsData[i].epochId, _claimsData[i].account, _claimsData[i].amount, _claimsData[i].merkleProof);
        }
    }

    /// @notice Transfer expired rewards to the expiredRewardsRecipient.
    /// @param _epochIds The list of epoch that will be claimed.
    function forwardExpiredRewards(uint64[] calldata _epochIds) external {
        uint256 len = _epochIds.length;
        if (len == 0) revert EmptyArray();
        uint256 i;
        uint256 totalExpiredRewards;
        for (; i < len; ++i) {
            uint64 epochId = _epochIds[i];
            uint256 expiredRewards = _getEpochExpiredRewards(epochId);
            totalExpiredRewards += expiredRewards;
            totalClaimedPerEpoch[epochId] += expiredRewards;

            emit ExpiredRewardsForwarded(epochId, expiredRewards);
        }
        totalClaimed += totalExpiredRewards;
        TOKEN.safeTransfer(expiredRewardsRecipient, totalExpiredRewards);
    }

    /// @notice Get the total rewards that can be forward to the recipient address for the list of epoch.
    /// @dev will revert if an epoch is not expired.
    /// @param _epochIds The list of epoch to check.
    function getExpiredEpochRewards(uint64[] calldata _epochIds) external view returns (uint256 totalExpiredRewards) {
        uint256 len = _epochIds.length;
        if (len == 0) revert EmptyArray();
        uint256 i;
        for (; i < len; ++i) {
            totalExpiredRewards += _getEpochExpiredRewards(_epochIds[i]);
        }
    }

    //-------------------------------------------
    // AccessManaged Functions
    //-------------------------------------------

    /// @notice Updates the merkleDrop for a specific epoch.
    /// @dev This function can only be called by AccessManager.
    /// @param _epoch The epoch to update.
    /// @param _merkleDrop The merkleDrop to update.
    function updateMerkleDrop(uint64 _epoch, MerkleDrop memory _merkleDrop) external restricted {
        if (_merkleDrop.expiryTime - _merkleDrop.startTime < EPOCH_LENGTH) revert EpochExpired();
        merkleDrops[_epoch] = _merkleDrop;
        emit MerkleDropUpdated(
            _epoch, _merkleDrop.root, _merkleDrop.totalAmount, _merkleDrop.startTime, _merkleDrop.expiryTime
        );
    }

    /// @notice Allow to rescue tokens own by the contract.
    /// @param _token The address of the token.
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens to rescue.
    function emergencyRescue(address _token, address _to, uint256 _amount) external restricted whenPaused {
        emit EmergencyRescued(_token, _to, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Update the recipient address that will receive expired rewards.
    /// @param _newExpiredRewardsRecipient the new recipient address.
    function updateExpiredRewardsRecipient(address _newExpiredRewardsRecipient) external restricted {
        if (_newExpiredRewardsRecipient == address(0)) revert AddressZero();
        expiredRewardsRecipient = _newExpiredRewardsRecipient;
        emit ExpiredRewardsRecipientUpdated(_newExpiredRewardsRecipient);
    }

    /// @notice Allow AccessManager to pause the contract.
    /// @dev This function can only be called by AccessManager.
    function pause() external restricted {
        _pause();
    }

    /// @notice Allow AccessManager to unpause the contract
    /// @dev This function can only be called by AccessManager
    function unpause() external restricted {
        _unpause();
    }

    //-------------------------------------------
    // Internal Functions
    //-------------------------------------------

    /// @notice Claims rewards.
    /// @param _account The address of the claimer.
    /// @param _amount The amount that the account should claim for the epoch.
    /// @param _proof The merkle proof that validates this claim.
    function _claim(uint64 _epochId, address _account, uint256 _amount, bytes32[] calldata _proof) private {
        MerkleDrop memory _merkleDrop = merkleDrops[_epochId];

        uint64 currentTimetamp = uint64(block.timestamp);
        if (currentTimetamp > _merkleDrop.expiryTime) revert EpochExpired();
        if (currentTimetamp < _merkleDrop.startTime) revert NotStarted();
        if (hasClaimed[_account][_epochId]) revert AlreadyClaimed();
        /// @dev Merkle leaves are double-hashed to avoid second preimage attack:
        /// https://www.rareskills.io/post/merkle-tree-second-preimage-attack
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_epochId, _account, _amount))));
        bool isValidProof = MerkleProof.verify(_proof, _merkleDrop.root, leaf);
        if (!isValidProof) revert ProofInvalid();
        totalClaimed += _amount;
        totalClaimedPerEpoch[_epochId] += _amount;
        if (totalClaimedPerEpoch[_epochId] > _merkleDrop.totalAmount) revert TotalEpochRewardsExceeded();

        hasClaimed[_account][_epochId] = true;
        totalClaimedPerUser[_account] += _amount;
        emit RewardsClaimed(_epochId, _account, _amount);
        TOKEN.safeTransfer(_account, _amount);
    }

    function _getEpochExpiredRewards(uint64 _epochId) private view returns (uint256 epochExpiredRewards) {
        MerkleDrop memory _merkleDrop = merkleDrops[_epochId];
        if (_merkleDrop.expiryTime >= uint64(block.timestamp)) revert EpochNotExpired();
        epochExpiredRewards = _merkleDrop.totalAmount - totalClaimedPerEpoch[_epochId];
    }
}
