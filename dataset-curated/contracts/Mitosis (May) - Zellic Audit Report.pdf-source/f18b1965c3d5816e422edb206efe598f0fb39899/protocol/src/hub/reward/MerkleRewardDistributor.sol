// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { MerkleProof } from '@oz/utils/cryptography/MerkleProof.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IMerkleRewardDistributor } from '../../interfaces/hub/reward/IMerkleRewardDistributor.sol';
import { ITreasury } from '../../interfaces/hub/reward/ITreasury.sol';
import { StdError } from '../../lib/StdError.sol';
import { MerkleRewardDistributorStorageV1 } from './MerkleRewardDistributorStorageV1.sol';

contract MerkleRewardDistributor is
  IMerkleRewardDistributor,
  AccessControlEnumerableUpgradeable,
  UUPSUpgradeable,
  MerkleRewardDistributorStorageV1
{
  using SafeERC20 for IERC20;
  using MerkleProof for bytes32[];

  /// @notice Role for manager (keccak256("MANAGER_ROLE"))
  bytes32 public constant MANAGER_ROLE = 0x241ecf16d79d0f8dbfb92cbc07fe17840425976cf0667f022fe9877caa831b08;

  /// @notice Maximum number of rewards that can be claimed in a single call.
  uint256 public constant MAX_CLAIM_VAULT_SIZE = 100;

  /// @notice Maximum number of batch claims that can be made in a single call.
  uint256 public constant MAX_CLAIM_STAGES_SIZE = 10;

  //=========== NOTE: INITIALIZATION FUNCTIONS ===========//

  constructor() {
    _disableInitializers();
  }

  function initialize(address admin, address treasury_) public initializer {
    require(admin != address(0), StdError.ZeroAddress('admin'));

    __AccessControlEnumerable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

    _setTreasury(_getStorageV1(), treasury_);
  }

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function lastStage() external view returns (uint256) {
    return _getStorageV1().lastStage;
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function root(uint256 stage_) external view returns (bytes32) {
    return _stage(_getStorageV1(), stage_).root;
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function rewardInfo(uint256 stage_) external view returns (address[] memory, uint256[] memory) {
    Stage storage s = _stage(_getStorageV1(), stage_);
    return (s.rewards, s.amounts);
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function treasury() external view returns (ITreasury) {
    return _getStorageV1().treasury;
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function encodeLeaf(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external pure returns (bytes32 leaf) {
    return _leaf(receiver, stage, vault, rewards, amounts);
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function claimable(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts,
    bytes32[] calldata proof
  ) external view returns (bool) {
    return _claimable(receiver, stage, vault, rewards, amounts, proof);
  }

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function claim(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts,
    bytes32[] calldata proof
  ) public {
    _claim(receiver, stage, vault, rewards, amounts, proof);
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function claimMultiple(
    address receiver,
    uint256 stage,
    address[] calldata vaults,
    address[][] calldata rewards,
    uint256[][] calldata amounts,
    bytes32[][] calldata proofs
  ) public {
    require(vaults.length == rewards.length, StdError.InvalidParameter('rewards.length'));
    require(vaults.length == amounts.length, StdError.InvalidParameter('amounts.length'));
    require(vaults.length == proofs.length, StdError.InvalidParameter('proofs.length'));
    require(vaults.length <= MAX_CLAIM_VAULT_SIZE, StdError.InvalidParameter('vaults.length'));

    for (uint256 i = 0; i < vaults.length; i++) {
      claim(receiver, stage, vaults[i], rewards[i], amounts[i], proofs[i]);
    }
  }

  /**
   * @inheritdoc IMerkleRewardDistributor
   */
  function claimBatch(
    address receiver,
    uint256[] calldata stages,
    address[][] calldata vaults,
    address[][][] calldata rewards,
    uint256[][][] calldata amounts,
    bytes32[][][] calldata proofs
  ) public {
    require(stages.length == vaults.length, StdError.InvalidParameter('vaults.length'));
    require(stages.length == rewards.length, StdError.InvalidParameter('rewards.length'));
    require(stages.length == amounts.length, StdError.InvalidParameter('amounts.length'));
    require(stages.length == proofs.length, StdError.InvalidParameter('proofs.length'));
    require(stages.length <= MAX_CLAIM_STAGES_SIZE, StdError.InvalidParameter('stages.length'));

    for (uint256 i = 0; i < stages.length; i++) {
      claimMultiple(receiver, stages[i], vaults[i], rewards[i], amounts[i], proofs[i]);
    }
  }

  // ============================ NOTE: ADMIN FUNCTIONS ============================ //

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

  // ============================ NOTE: MANAGER FUNCTIONS ============================ //

  function fetchRewards(uint256 stage, uint256 nonce, address vault, address reward, uint256 amount)
    external
    onlyRole(MANAGER_ROLE)
  {
    StorageV1 storage $ = _getStorageV1();

    require(stage == $.lastStage, IMerkleRewardDistributor__NotCurrentStage(stage));
    require(nonce == _stage($, stage).nonce, IMerkleRewardDistributor__InvalidStageNonce(stage, nonce));

    _fetchRewards($, stage, vault, reward, amount);
  }

  function fetchRewardsMultiple(
    uint256 stage,
    uint256 nonce,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external onlyRole(MANAGER_ROLE) {
    StorageV1 storage $ = _getStorageV1();

    require(stage == $.lastStage, IMerkleRewardDistributor__NotCurrentStage(stage));
    require(nonce == _stage($, stage).nonce, IMerkleRewardDistributor__InvalidStageNonce(stage, nonce));

    for (uint256 i = 0; i < rewards.length; i++) {
      _fetchRewards($, stage, vault, rewards[i], amounts[i]);
    }
  }

  function fetchRewardsBatch(
    uint256 stage,
    uint256 nonce,
    address[] calldata vaults,
    address[][] calldata rewards,
    uint256[][] calldata amounts
  ) external onlyRole(MANAGER_ROLE) {
    StorageV1 storage $ = _getStorageV1();

    require(stage == $.lastStage, IMerkleRewardDistributor__NotCurrentStage(stage));
    require(nonce == _stage($, stage).nonce, IMerkleRewardDistributor__InvalidStageNonce(stage, nonce));
    require(vaults.length == rewards.length, StdError.InvalidParameter('rewards.length'));

    for (uint256 i = 0; i < vaults.length; i++) {
      for (uint256 j = 0; j < rewards[i].length; j++) {
        _fetchRewards($, stage, vaults[i], rewards[i][j], amounts[i][j]);
      }
    }
  }

  function addStage(
    bytes32 merkleRoot,
    uint256 stage,
    uint256 nonce,
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external onlyRole(MANAGER_ROLE) returns (uint256 merkleStage) {
    StorageV1 storage $ = _getStorageV1();
    Stage storage s = _stage($, stage);

    require(stage == $.lastStage, IMerkleRewardDistributor__NotCurrentStage(stage));
    require(nonce == s.nonce, IMerkleRewardDistributor__InvalidStageNonce(stage, nonce));
    require(rewards.length == amounts.length, StdError.InvalidParameter('amounts.length'));

    for (uint256 i = 0; i < rewards.length; i++) {
      address reward = rewards[i];
      uint256 amount = amounts[i];
      require(_availableRewardAmount($, reward) >= amount, IMerkleRewardDistributor__InvalidAmount());
      $.reservedRewardAmounts[reward] += amount;
    }

    _addStage($, merkleRoot, rewards, amounts);

    return merkleStage;
  }

  // ============================ NOTE: INTERNAL FUNCTIONS ============================ //

  function _setTreasury(StorageV1 storage $, address treasury_) internal {
    require(treasury_.code.length > 0, StdError.InvalidAddress('treasury'));

    ITreasury oldTreasury = $.treasury;
    $.treasury = ITreasury(treasury_);

    emit TreasuryUpdated(address(oldTreasury), treasury_);
  }

  function _fetchRewards(StorageV1 storage $, uint256 stage, address vault, address reward, uint256 amount) internal {
    Stage storage s = _stage($, stage);
    uint256 nonce = s.nonce++;

    $.treasury.dispatch(vault, reward, amount, address(this));

    emit RewardsFetched(stage, nonce, vault, reward, amount);
  }

  function _addStage(StorageV1 storage $, bytes32 root_, address[] calldata rewards, uint256[] calldata amounts)
    internal
    onlyRole(MANAGER_ROLE)
    returns (uint256 stage)
  {
    $.lastStage += 1;
    Stage storage s = _stage($, $.lastStage);
    s.root = root_;
    s.rewards = rewards;
    s.amounts = amounts;

    emit StageAdded($.lastStage, root_, rewards, amounts);

    return $.lastStage;
  }

  function _stage(StorageV1 storage $, uint256 stage) internal view returns (Stage storage) {
    return $.stages[stage];
  }

  function _claimable(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts,
    bytes32[] calldata proof
  ) internal view returns (bool) {
    StorageV1 storage $ = _getStorageV1();
    Stage storage s = _stage($, stage);

    bytes32 leaf = _leaf(receiver, stage, vault, rewards, amounts);

    return !s.claimed[receiver][vault] && proof.verify(s.root, leaf);
  }

  function _claim(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts,
    bytes32[] calldata proof
  ) internal {
    StorageV1 storage $ = _getStorageV1();
    Stage storage s = _stage($, stage);
    require(!s.claimed[receiver][vault], IMerkleRewardDistributor__AlreadyClaimed());

    uint256 rewardsLen = rewards.length;
    bytes32 leaf = _leaf(receiver, stage, vault, rewards, amounts);
    require(proof.verify(s.root, leaf), IMerkleRewardDistributor__InvalidProof());
    require(rewardsLen == amounts.length, StdError.InvalidParameter('amounts.length'));

    s.claimed[receiver][vault] = true;
    for (uint256 i = 0; i < rewardsLen; i++) {
      $.reservedRewardAmounts[rewards[i]] -= amounts[i];
    }

    for (uint256 i = 0; i < rewardsLen; i++) {
      IERC20(rewards[i]).safeTransfer(receiver, amounts[i]);
    }

    emit Claimed(receiver, stage, vault, rewards, amounts);
  }

  function _availableRewardAmount(StorageV1 storage $, address reward) internal view returns (uint256) {
    return IERC20(reward).balanceOf(address(this)) - $.reservedRewardAmounts[reward];
  }

  function _leaf(address receiver, uint256 stage, address vault, address[] calldata rewards, uint256[] calldata amounts)
    internal
    pure
    returns (bytes32 leaf)
  {
    // double-hashing to prevent second preimage attacks:
    // https://flawed.net.nz/2018/02/21/attacking-merkle-trees-with-a-second-preimage-attack/
    return keccak256(bytes.concat(keccak256(abi.encodePacked(receiver, stage, vault, rewards, amounts))));
  }
}
