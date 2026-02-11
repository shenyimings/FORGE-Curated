// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @dev File that contains all the errors for the project
 * @notice this file should be then imported in the contract files to use the errors.
 */

/**** CofNErrors ****/
error NegativeValue();
error DnTooLarge();

/**** PythonUtilErrors ****/
error bytesLargerThanUint256();
error diffGreaterThanUint256();

/**** PoolErrors ****/
error YTokenNotAllowed();
error XandYTokensAreTheSame();
error BeyondLiquidity();
error LPFeeAboveMax(uint16 proposedFee, uint16 maxFee);
error YTokenDecimalsGT18();
error XTokenDecimalsIsNot18();
error ZeroValueNotAllowed();
error InvalidToken();
error XOutOfBounds(uint256 howMuch);
error NotEnoughCollateral();
error ProtocolFeeAboveMax(uint16 proposedFee, uint16 maxFee);
error NotProtocolFeeCollector();
error NotProposedProtocolFeeCollector();
error NoProtocolFeeCollector();
error CannotDepositInactiveLiquidity();
error InactiveLiquidityExceedsLimit();
error CCannotBeZero();
error VCannotBeZero();
error xMinCannotBeZero();
error MaxSlippageReached();
error LPTokenWithdrawalAmountExceedsAllowance();
error QTooHigh();
error TransactionExpired();

/**** PoolFactoryErrors ****/
error NotAnAllowedDeployer();

/**** Input Errors ****/
error ZeroAddress();

/**** ERC721 Errors ****/
error URIQueryForNonexistentToken();
error PoolNotAllowed();
error TokenNotFromPool();
error PoolAlreadyAllowed();
error NotProposedFactory(address factoryAddressProposed);
error NotFactory();

/**** Ownership Errors ****/
error RenouncingOwnershipForbidden();
