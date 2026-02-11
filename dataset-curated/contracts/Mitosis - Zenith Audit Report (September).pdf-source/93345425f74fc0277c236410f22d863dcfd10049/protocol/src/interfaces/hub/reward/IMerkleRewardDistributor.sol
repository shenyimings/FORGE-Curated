// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ITreasury } from './ITreasury.sol';

/**
 * @title IMerkleRewardDistributor
 * @notice Interface for the Merkle based reward distributor
 */
interface IMerkleRewardDistributor {
  event RewardsFetched(uint256 indexed id, uint256 nonce, address indexed vault, address reward, uint256 amount);

  event StageAdded(uint256 indexed stage, bytes32 root, address[] rewards, uint256[] amounts);

  event Claimed(
    address indexed receiver, uint256 indexed stage, address indexed vault, address[] rewards, uint256[] amounts
  );

  event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

  /**
   * @notice Error thrown when attempting to claim an already claimed reward.
   */
  error IMerkleRewardDistributor__AlreadyClaimed();

  /**
   * @notice Error thrown when an invalid Merkle proof is provided.
   */
  error IMerkleRewardDistributor__InvalidProof();

  /**
   * @notice Error thrown when an invalid amount is provided for claim or adding stage.
   */
  error IMerkleRewardDistributor__InvalidAmount();

  error IMerkleRewardDistributor__NotCurrentStage(uint256 stage);

  error IMerkleRewardDistributor__InvalidStageNonce(uint256 stage, uint256 nonce);

  // ============================ NOTE: VIEW FUNCTIONS ============================ //

  /**
   * @notice Returns the last stage. If no stage exists, it returns 0.
   */
  function lastStage() external view returns (uint256);

  /**
   * @notice Returns the root hash of the specified stage. If the stage does not exist, it returns 0.
   */
  function root(uint256 stage_) external view returns (bytes32);

  /**
   * @notice Returns the reward information of the specified stage. If the stage does not exist, it returns empty array.
   */
  function rewardInfo(uint256 stage_) external view returns (address[] memory rewards, uint256[] memory amounts);

  /**
   * @notice Returns the ITreasury.
   */
  function treasury() external view returns (ITreasury);

  /**
   * @notice Makes a leaf hash that expected to be used in the merkle tree.
   * @param stage The stage number.
   * @param receiver The receiver address.
   * @param vault The vault address.
   * @param rewards The reward token addresses.
   * @param amounts The reward amounts.
   */
  function encodeLeaf(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external pure returns (bytes32 leaf);

  /**
   * @notice Checks if the account can claim the rewards for the specified vault in the specified stage.
   * @param receiver The receiver address.
   * @param stage The stage number.
   * @param vault The vault address.
   * @param rewards The reward token addresses.
   * @param amounts The reward amounts.
   * @param proof The merkle proof.
   */
  function claimable(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts,
    bytes32[] calldata proof
  ) external view returns (bool);

  // ============================ NOTE: MUTATIVE FUNCTIONS ============================ //

  /**
   * @notice Claims rewards for the specified vault in the specified stage.
   */
  function claim(
    address receiver,
    uint256 stage,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts,
    bytes32[] calldata proof
  ) external;

  /**
   * @notice Claims rewards for the multiple vaults in the specified stage.
   */
  function claimMultiple(
    address receiver,
    uint256 stage,
    address[] calldata vaults,
    address[][] calldata rewards,
    uint256[][] calldata amounts,
    bytes32[][] calldata proofs
  ) external;

  /**
   * @notice Claims rewards for the multiple vaults in the multiple stages.
   */
  function claimBatch(
    address receiver,
    uint256[] calldata stages,
    address[][] calldata vaults,
    address[][][] calldata rewards,
    uint256[][][] calldata amounts,
    bytes32[][][] calldata proofs
  ) external;

  // ============================ NOTE: MANAGER FUNCTIONS ============================ //

  /**
   * @notice Fetches reward from the vault to the specified stage.
   */
  function fetchRewards(uint256 stage, uint256 nonce, address vault, address reward, uint256 amount) external;

  /**
   * @notice Fetches rewards from the vaults to the specified stage.
   */
  function fetchRewardsMultiple(
    uint256 stage,
    uint256 nonce,
    address vault,
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external;

  /**
   * @notice Fetches rewards from the multiple vaults to the specified stage.
   */
  function fetchRewardsBatch(
    uint256 stage,
    uint256 nonce,
    address[] calldata vaults,
    address[][] calldata rewards,
    uint256[][] calldata amounts
  ) external;

  /**
   * @notice Adds a new stage with the specified root hash.
   * @param root_ The root hash of the merkle tree.
   * @param stage_ The stage number of the added root hash.
   * @param nonce The nonce number of the stage.
   * @param rewards The reward token addresses.
   * @param amounts The reward amounts.
   * @return stage The stage number of the added root hash.
   */
  function addStage(
    bytes32 root_,
    uint256 stage_,
    uint256 nonce,
    address[] calldata rewards,
    uint256[] calldata amounts
  ) external returns (uint256 stage);
}
