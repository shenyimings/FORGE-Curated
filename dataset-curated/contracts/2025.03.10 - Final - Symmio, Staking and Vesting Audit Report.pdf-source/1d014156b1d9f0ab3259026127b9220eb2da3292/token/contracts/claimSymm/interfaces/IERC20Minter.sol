// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMintableERC20
 * @dev Interface for mintable ERC-20 tokens.
 */
interface IMintableERC20 is IERC20 {
	/**
	 * @dev Mints tokens to a specified address.
	 * @param account The address to mint tokens to.
	 * @param amount The amount of tokens to mint.
	 */
	function mint(address account, uint256 amount) external;
}
