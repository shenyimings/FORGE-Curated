// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IConsensusValidatorEntrypoint {
  event PermittedCallerSet(address caller, bool isPermitted);

  event MsgRegisterValidator(
    address valAddr, bytes pubKey, address initialCollateralOwner, uint256 initialCollateralAmountGwei
  );
  event MsgDepositCollateral(address valAddr, address collateralOwner, uint256 amountGwei);
  event MsgWithdrawCollateral(
    address valAddr, address collateralOwner, address receiver, uint256 amountGwei, uint48 maturesAt
  );
  event MsgTransferCollateralOwnership(address valAddr, address prevOwner, address newOwner);
  event MsgUnjail(address valAddr);
  event MsgUpdateExtraVotingPower(address valAddr, uint256 extraVotingPowerWei);

  /**
   * @notice Register a validator in the consensus layer.
   * @dev The collateral might be returned if the validator is not registered in the consensus layer.
   * @param valAddr The address of the validator.
   * @param pubKey The compressed 33-byte secp256k1 public key of the validator.
   * @param initialCollateralOwner The initial address to own the initial collateral.
   */
  function registerValidator(address valAddr, bytes calldata pubKey, address initialCollateralOwner) external payable;

  /**
   * @notice Deposit collateral to the validator in the consensus layer.
   * @dev The collateral might be returned if the validator is not registered in the consensus layer.
   * @param valAddr The address of the validator.
   * @param collateralOwner The address to own the collateral.
   */
  function depositCollateral(address valAddr, address collateralOwner) external payable;

  /**
   * @notice Request a withdrawal of collateral from the validator in the consensus layer.
   * The collateral is sent to the receiver address after the request matures.
   * @dev Nothing happens if the validator is not registered in the consensus layer or the collateral owner don't own enough collateral.
   * @param valAddr The address of the validator.
   * @param collateralOwner The address that owns the collateral.
   * @param receiver The address to receive the withdrawn collateral.
   * @param amount The amount of collateral to withdraw.
   * @param maturesAt The time when the withdrawal request matures. After this time, the collateral will be sent to the receiver.
   */
  function withdrawCollateral(
    address valAddr,
    address collateralOwner,
    address receiver,
    uint256 amount,
    uint48 maturesAt
  ) external;

  /**
   * @notice Transfer the ownership of the collateral to a new address.
   * @dev Nothing happens if the validator is not registered in the consensus layer.
   * @param valAddr The address of the validator.
   * @param prevOwner The address that owns the collateral.
   * @param newOwner The address to receive the ownership of the collateral.
   */
  function transferCollateralOwnership(address valAddr, address prevOwner, address newOwner) external;

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
