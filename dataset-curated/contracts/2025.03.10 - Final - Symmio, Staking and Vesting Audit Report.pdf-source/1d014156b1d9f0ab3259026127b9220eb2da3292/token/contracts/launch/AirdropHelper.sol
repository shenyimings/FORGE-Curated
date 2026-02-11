// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AirdropHelper
 * @notice Manages token airdrops for the Symm token on Aerodrome
 * @dev Implements a secure airdrop mechanism with owner controls and batch processing
 */
contract AirdropHelper is Ownable2Step {
	using SafeERC20 for IERC20;

	// Constants
	IERC20 public constant SYMM_TOKEN = IERC20(0x800822d361335b4d5F352Dac293cA4128b5B605f);

	// State variables
	address[] private _airdropRecipients;
	uint256[] private _airdropAmounts;
	uint256 public totalConfiguredAirdrop;
	uint256 public nextAirdropIndex;
	uint256 public totalProcessedAirdrop;

	// Events
	event AirdropConfigured(uint256 totalAmount, uint256 recipientCount);
	event AirdropConfigCleared();
	event AirdropBatchExecuted(uint256 startIndex, uint256 endIndex, uint256 batchAmount);
	event AirdropCompleted(uint256 totalAmount, uint256 recipientCount);
	event FundsRescued(address token, uint256 amount);

	// Custom errors
	error ArrayLengthMismatch();
	error EmptyArrays();
	error InvalidRecipient();
	error InvalidAmount();
	error ZeroAddress();
	error InvalidBatchSize();
	error NoActiveAirdrop();

	constructor() Ownable(msg.sender) {}

	/**
	 * @notice Configures the airdrop with recipients and amounts
	 * @param recipients Array of recipient addresses
	 * @param amounts Array of corresponding amounts
	 */
	function configureAirdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
		if (recipients.length != amounts.length) revert ArrayLengthMismatch();
		if (recipients.length == 0) revert EmptyArrays();

		for (uint256 i = 0; i < recipients.length; ) {
			if (recipients[i] == address(0)) revert InvalidRecipient();
			if (amounts[i] == 0) revert InvalidAmount();

			_airdropRecipients.push(recipients[i]);
			_airdropAmounts.push(amounts[i]);
			totalConfiguredAirdrop += amounts[i];

			unchecked {
				++i;
			}
		}

		emit AirdropConfigured(totalConfiguredAirdrop, recipients.length);
	}

	/**
	 * @notice Clears the current airdrop configuration
	 */
	function clearAirdropConfig() external onlyOwner {
		delete _airdropRecipients;
		delete _airdropAmounts;
		totalConfiguredAirdrop = 0;
		nextAirdropIndex = 0;
		totalProcessedAirdrop = 0;
		emit AirdropConfigCleared();
	}

	/**
	 * @notice Executes a batch of the configured airdrop
	 * @param batchSize Number of transfers to process in this batch
	 */
	function transferAirdrops(uint256 batchSize) external onlyOwner {
		if (batchSize == 0) revert InvalidBatchSize();
		if (_airdropRecipients.length == 0) revert NoActiveAirdrop();

		uint256 endIndex = nextAirdropIndex + batchSize;
		if (endIndex > _airdropRecipients.length) {
			endIndex = _airdropRecipients.length;
		}

		uint256 batchAmount;

		for (uint256 i = nextAirdropIndex; i < endIndex; ) {
			SYMM_TOKEN.safeTransfer(_airdropRecipients[i], _airdropAmounts[i]);
			batchAmount += _airdropAmounts[i];

			unchecked {
				++i;
			}
		}

		totalProcessedAirdrop += batchAmount;

		emit AirdropBatchExecuted(nextAirdropIndex, endIndex, batchAmount);

		// Update the next starting index
		nextAirdropIndex = endIndex;

		// If we've processed all recipients, clear the configuration
		if (nextAirdropIndex == _airdropRecipients.length) {
			uint256 finalRecipientCount = _airdropRecipients.length;
			uint256 finalTotalAmount = totalProcessedAirdrop;

			delete _airdropRecipients;
			delete _airdropAmounts;
			totalConfiguredAirdrop = 0;
			nextAirdropIndex = 0;
			totalProcessedAirdrop = 0;

			emit AirdropCompleted(finalTotalAmount, finalRecipientCount);
		}
	}

	/**
	 * @notice Returns the current airdrop configuration and progress
	 * @return recipients Array of recipient addresses
	 * @return amounts Array of corresponding amounts
	 * @return processedIndex Number of recipients processed so far
	 */
	function getAirdropConfig() external view returns (address[] memory recipients, uint256[] memory amounts, uint256 processedIndex) {
		return (_airdropRecipients, _airdropAmounts, nextAirdropIndex);
	}

	/**
	 * @notice Returns the remaining number of recipients to process
	 * @return remaining Number of recipients left to process
	 */
	function getRemainingAirdrops() external view returns (uint256 remaining) {
		return _airdropRecipients.length - nextAirdropIndex;
	}

	/**
	 * @notice Rescues any tokens accidentally sent to the contract
	 * @param tokenAddress Address of the token to rescue
	 */
	function rescueFunds(address tokenAddress) external onlyOwner {
		if (tokenAddress == address(0)) revert ZeroAddress();

		IERC20 token = IERC20(tokenAddress);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(owner(), balance);

		emit FundsRescued(tokenAddress, balance);
	}
}
