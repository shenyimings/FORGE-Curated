// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IMintableERC20 } from "./interfaces/IERC20Minter.sol";
import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SymmAllocationClaimer
 * @dev Contract for managing user allocations with 18 decimal precision
 */
contract SymmAllocationClaimer is AccessControlEnumerable, Pausable {
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
	uint256 public constant MAX_ISSUABLE_TOKEN = 400_000_000 * 1e18;

	uint256 public immutable mintFactor; // decimal 18
	address public immutable token;

	address public symmioFoundationAddress;
	uint256 public totalAllocation;
	uint256 public totalUserClaimedAmount;
	uint256 public adminClaimableAmount;
	uint256 public totalMintAmount;

	// Mapping from user address to their allocation (with 18 decimals precision)
	mapping(address => uint256) public userAllocations;
	mapping(address => uint256) public userClaimedAmounts;

	// Events
	event BatchAllocationsSet(address[] users, uint256[] allocations);
	event Claimed(address user, uint256 amount);
	event AdminClaimed(address sender, address receiver, uint256 amount);
	event SymmioFoundationAddressSet(address newAddress);

	// Errors
	error UserHasNoAllocation(address user);
	error AdminClaimAmountExceedsAvailable(uint256 availableAmount, uint256 claimRequestAmount);
	error ZeroAddress();
	error InvalidFactor();
	error ArrayLengthMismatch();
	error EmptyArrays();
	error TotalAllocationExceedsMax(uint256 totalAllocation, uint256 maxIssuable);

	/**
	 * @dev Initializes the contract by setting roles and initial parameters.
	 * @param admin Address that will be granted the DEFAULT_ADMIN_ROLE.
	 * @param setter Address that will be granted the SETTER_ROLE.
	 * @param _token Address of the token to be minted.
	 * @param _symmioFoundation Address of the symmio foundation.
	 * @param _mintFactor The mint factor (with 18 decimals precision).
	 */
	constructor(address admin, address setter, address _token, address _symmioFoundation, uint256 _mintFactor) {
		if (_token == address(0) || admin == address(0) || setter == address(0) || _symmioFoundation == address(0)) {
			revert ZeroAddress();
		}
		if (_mintFactor > 1e18 || _mintFactor == 0) {
			revert InvalidFactor();
		}

		token = _token;
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(SETTER_ROLE, setter);
		symmioFoundationAddress = _symmioFoundation;
		mintFactor = _mintFactor;

		emit SymmioFoundationAddressSet(symmioFoundationAddress);
	}

	/**
	 * @dev Sets a new symmio foundation address.
	 * @param _symmioFoundationAddress The new address of the symmio foundation.
	 */
	function setSymmioFoundationAddress(address _symmioFoundationAddress) external onlyRole(SETTER_ROLE) {
		if (_symmioFoundationAddress == address(0)) {
			revert ZeroAddress();
		}
		symmioFoundationAddress = _symmioFoundationAddress;
		emit SymmioFoundationAddressSet(symmioFoundationAddress);
	}

	/**
	 * @dev Sets allocations for multiple users in a single transaction
	 * Updates totalAllocation by subtracting old values and adding new ones
	 * @param users Array of user addresses
	 * @param allocations Array of allocation values with 18 decimals
	 */
	function setBatchAllocations(address[] calldata users, uint256[] calldata allocations) external onlyRole(SETTER_ROLE) {
		if (users.length != allocations.length) revert ArrayLengthMismatch();
		if (users.length == 0) revert EmptyArrays();
		for (uint256 i = 0; i < users.length; i++) {
			if (users[i] == address(0)) revert ZeroAddress();
			// Subtract old allocation from total
			totalAllocation = totalAllocation - userAllocations[users[i]];
			// Set new allocation
			userAllocations[users[i]] = allocations[i];
			// Add new allocation to total
			totalAllocation = totalAllocation + allocations[i];
		}
		if (totalAllocation > MAX_ISSUABLE_TOKEN) {
			revert TotalAllocationExceedsMax(totalAllocation, MAX_ISSUABLE_TOKEN);
		}
		emit BatchAllocationsSet(users, allocations);
	}

	/**
	 * @dev Allows a user to claim their allocation as minted ERC20 tokens
	 */
	function claim() public whenNotPaused {
		if (userAllocations[msg.sender] == 0) {
			revert UserHasNoAllocation(msg.sender);
		}
		uint256 amountToClaim = (userAllocations[msg.sender] * mintFactor) / 1e18;
		adminClaimableAmount += (userAllocations[msg.sender] - amountToClaim);
		totalMintAmount += amountToClaim;
		totalUserClaimedAmount += amountToClaim;
		userAllocations[msg.sender] = 0;
		userClaimedAmounts[msg.sender] += amountToClaim;
		IMintableERC20(token).mint(msg.sender, amountToClaim);
		emit Claimed(msg.sender, amountToClaim);
	}

	/**
	 * @dev Allows the admin to claim accumulated admin claimable tokens.
	 * @param amount The amount to claim.
	 */
	function adminClaim(uint256 amount) external onlyRole(MINTER_ROLE) {
		if (amount > adminClaimableAmount) {
			revert AdminClaimAmountExceedsAvailable(adminClaimableAmount, amount);
		}
		totalMintAmount += amount;
		adminClaimableAmount -= amount;
		IMintableERC20(token).mint(symmioFoundationAddress, amount);
		emit AdminClaimed(msg.sender, symmioFoundationAddress, amount);
	}

	/// @notice Pauses the contract, preventing claims.
	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	/// @notice Unpauses the contract, allowing claims.
	function unpause() external onlyRole(UNPAUSER_ROLE) {
		_unpause();
	}
}
