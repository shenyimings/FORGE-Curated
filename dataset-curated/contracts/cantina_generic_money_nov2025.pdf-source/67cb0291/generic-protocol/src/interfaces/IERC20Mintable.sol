// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IERC20Mintable Interface
 * @notice Interface for an ERC20 token with controlled minting and burning capabilities.
 * @dev This interface extends the standard ERC20 functionality to include administrative
 * functions for token supply management with proper access control. The mint and burn
 * functions are restricted to the contract owner to ensure controlled supply changes.
 *
 * Key Features:
 * - ERC20 compliance for standard token operations
 * - Controlled minting and burning functionality with owner access control
 *
 * Events:
 * - Mint: Emitted when new tokens are minted
 * - Burn: Emitted when tokens are burned
 *
 * Access Control:
 * - mint(): Only owner
 * - burn(): Only owner
 * - ERC20 operations: All users
 */
interface IERC20Mintable {
    /**
     * @notice Emitted when new tokens are minted to an address.
     * @dev This event is emitted after successful execution of the mint function.
     * It provides transparency for token supply increases.
     * @param to The address receiving the minted tokens
     * @param amount Number of tokens minted
     */
    event Mint(address indexed to, uint256 amount);

    /**
     * @notice Emitted when tokens are burned from an address.
     * @dev This event is emitted after successful execution of the burn function.
     * It provides transparency for token supply decreases.
     * @param from Address whose tokens are burned
     * @param amount Number of tokens burned
     */
    event Burn(address indexed from, uint256 amount);

    /**
     * @notice Mints new tokens to the specified address, increasing total supply.
     * @dev Only callable by the contract owner.
     * This function increases both the total supply and the recipient's balance.
     *
     * Requirements:
     * - Caller must be the owner
     * - `to` address must not be zero
     *
     * Emits:
     * - {Mint} event with recipient and amount
     * - {Transfer} event from zero address to recipient
     *
     * @param to Address to receive the newly minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens from the specified address, decreasing total supply.
     * @dev Only callable by the contract owner.
     * This function decreases both the total supply and the target address's balance.
     *
     * Requirements:
     * - Caller must be the owner
     * - `from` address must not be zero
     * - `from` must have sufficient balance
     * - If `from` is different from `spender`, `spender` must have allowance for `from`'s tokens
     *
     * Emits:
     * - {Burn} event with source address and amount
     * - {Transfer} event from source address to zero address
     *
     * @param from Address to burn tokens from
     * @param spender Address initiating the burn (for allowance checks if different from `from`)
     * @param amount Amount of tokens to burn
     */
    function burn(address from, address spender, uint256 amount) external;
}
