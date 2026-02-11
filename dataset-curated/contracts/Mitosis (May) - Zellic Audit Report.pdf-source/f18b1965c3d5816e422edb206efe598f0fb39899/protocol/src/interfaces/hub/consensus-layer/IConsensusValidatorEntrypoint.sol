// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IConsensusValidatorEntrypoint {
  event PermittedCallerSet(address caller, bool isPermitted);

  event MsgRegisterValidator(
    address valAddr, bytes pubKey, uint256 initialCollateralAmountGwei, address collateralRefundAddr
  );
  event MsgDepositCollateral(address valAddr, uint256 amountGwei, address collateralRefundAddr);
  event MsgWithdrawCollateral(address valAddr, uint256 amountGwei, address receiver, uint48 maturesAt);
  event MsgUnjail(address valAddr);
  event MsgUpdateExtraVotingPower(address valAddr, uint256 extraVotingPowerWei);

  /**
   * @notice Register a validator in the consensus layer.
   * @dev The collateral might be returned if the validator is not registered in the consensus layer.
   * @param valAddr The address of the validator.
   * @param pubKey The compressed 33-byte secp256k1 public key of the validator.
   * @param collateralRefundAddr The address to receive the collateral if registration fails.
   */
  function registerValidator(address valAddr, bytes calldata pubKey, address collateralRefundAddr) external payable;

  /**
   * @notice Deposit collateral to the validator in the consensus layer.
   * @dev The collateral might be returned if the validator is not registered in the consensus layer.
   * @param valAddr The address of the validator.
   * @param collateralRefundAddr The address to receive the deposited collateral if deposit fails.
   */
  function depositCollateral(address valAddr, address collateralRefundAddr) external payable;

  /**
   * @notice Request a withdrawal of collateral from the validator in the consensus layer.
   * The collateral is sent to the receiver address after the request matures.
   * @dev Nothing happens if the validator is not registered in the consensus layer or has insufficient collateral.
   * @param valAddr The address of the validator.
   * @param amount The amount of collateral to withdraw.
   * @param receiver The address to receive the withdrawn collateral.
   * @param maturesAt The time when the withdrawal request matures. After this time, the collateral will be sent to the receiver.
   */
  function withdrawCollateral(address valAddr, uint256 amount, address receiver, uint48 maturesAt) external;

  /**
   * @notice Unjail a validator in the consensus layer.
   * @dev Nothing happens if the validator is not jailed in the consensus layer.
   * @param valAddr The address of the validator.
   */
  function unjail(address valAddr) external;

  /**
   * @notice Update (overwrite) the extra voting power of a validator in the consensus layer.
   * @dev Nothing happens if the validator is not registered in the consensus layer.
   * @param valAddr The address of the validator.
   * @param extraVotingPower The new extra voting power of the validator.
   */
  function updateExtraVotingPower(address valAddr, uint256 extraVotingPower) external;
}
