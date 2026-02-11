// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAegisRewards {
  function claimRewards(bytes32[] memory ids, uint256[] memory amounts, bytes memory signature) external;

  function depositRewards(bytes calldata requestId, uint256 amount) external;
}

interface IAegisRewardsEvents {
  /// @dev Event emitted when YUSD rewards is deposited to the contract
  event DepositRewards(bytes32 id, uint256 amount, uint256 timestamp);

  /// @dev Event emitted when rewards with id are finalized
  event FinalizeRewards(bytes32 id, uint256 expiry);

  /// @dev Event emitted when expired rewards withdrawn
  event WithdrawExpiredRewards(bytes32 id, address to, uint256 amount);

  /// @dev Event emitted when user claims rewards
  event ClaimRewards(address indexed wallet, bytes32[] ids, uint256 totalAmount);

  /// @dev Event emitted when AegisConfig contract address is changed
  event SetAegisConfigAddress(address indexed config);

  /// @dev Event emitted when AegisMinting contract address is changed
  event SetAegisMintingAddress(address indexed minting);
}

interface IAegisRewardsErrors {
  error ZeroAddress();
  error InvalidAddress();
  error ZeroRewards();
  error UnknownRewards();
}
