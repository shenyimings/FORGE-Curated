// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IERC20Mintable } from "../interfaces/IERC20Mintable.sol";

/**
 * @title ERC20Mintable
 * @notice An ERC20 token with controlled minting and burning capabilities.
 * @dev Inherits from OpenZeppelin's ERC20, ERC20Permit, and Ownable2Step for secure ownership transfer.
 * The owner has exclusive rights to mint and burn tokens, ensuring controlled supply management.
 *
 * Key Features:
 * - Standard ERC20 functionality for token transfers and balances
 * - EIP-2612 permit functionality for gasless approvals
 * - Owner-restricted minting and burning of tokens
 * - Two-step ownership transfer for enhanced security
 *
 * Security Considerations:
 * - Only the owner can mint or burn tokens, preventing unauthorized supply changes.
 * - Renouncing ownership is disabled to ensure the contract always has an owner for access control.
 */
contract ERC20Mintable is IERC20Mintable, Ownable2Step, ERC20Permit {
    /**
     * @notice Error thrown when attempting to renounce ownership.
     * @dev ERC20Mintable intentionally disables ownership renunciation to ensure the contract
     * always has an owner for mint/burn access control.
     */
    error RenounceOwnershipDisabled();

    /**
     * @notice Initializes the ERC20Mintable token with metadata and sets the owner.
     * @dev The owner address gets mint/burn privileges.
     * @param owner Address to be set as the owner
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     */
    constructor(
        address owner,
        string memory name,
        string memory symbol
    )
        Ownable(owner)
        ERC20(name, symbol)
        ERC20Permit(name)
    { }

    /**
     * @notice Mints new ERC20Mintable tokens to the specified address, increasing total supply.
     * @dev Only callable by the owner. Increases both total supply and recipient balance.
     *
     * Requirements:
     * - Caller must be the owner
     * - `to` cannot be the zero address
     *
     * Emits:
     * - {Mint} event with recipient and amount
     * - {Transfer} event from zero address to recipient
     *
     * @param to Address to receive the newly minted tokens
     * @param amount Amount of tokens to mint
     *
     * @custom:security Owner-only access prevents unauthorized inflation
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /**
     * @notice Burns tokens from the specified address, decreasing total supply.
     * @dev Only callable by the owner. Decreases both total supply and target balance.
     *
     * Requirements:
     * - Caller must be the owner
     * - `from` cannot be the zero address
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
     *
     * @custom:security Owner-only access prevents unauthorized deflation
     */
    function burn(address from, address spender, uint256 amount) external onlyOwner {
        _burn(from, amount);
        if (from != spender) _spendAllowance(from, spender, amount);
        emit Burn(from, amount);
    }

    /**
     * @notice Renouncing ownership is intentionally disabled for ERC20Mintable.
     * @dev This function always reverts to ensure the contract always has an owner
     * for mint/burn access control. This prevents accidental or malicious loss
     * of administrative control.
     *
     * @custom:security Always reverts to maintain ownership integrity
     */
    function renounceOwnership() public pure override {
        revert RenounceOwnershipDisabled();
    }
}
