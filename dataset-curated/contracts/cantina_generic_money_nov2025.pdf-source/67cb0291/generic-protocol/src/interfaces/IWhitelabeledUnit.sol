// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IWhitelabeledUnit
 * @notice Interface for whitelabeled unit tokens that wrap underlying value units
 * @dev This interface defines the core functionality for wrapping and unwrapping unit tokens
 * within the Generic Protocol ecosystem.
 */
interface IWhitelabeledUnit {
    /**
     * @notice Emitted when underlying unit tokens are wrapped into whitelabeled tokens
     * @param owner The address that received the newly minted whitelabeled tokens
     * @param amount The quantity of tokens wrapped (same amount of underlying tokens consumed and whitelabeled tokens
     * minted)
     */
    event Wrapped(address indexed owner, uint256 amount);
    /**
     * @notice Emitted when whitelabeled tokens are unwrapped back to underlying unit tokens
     * @param owner The address that owned the whitelabeled tokens during the unwrap
     * @param recipient The address that received the underlying unit tokens
     * @param amount The quantity of tokens unwrapped (same amount of whitelabeled tokens burned and underlying tokens
     * released)
     */
    event Unwrapped(address indexed owner, address indexed recipient, uint256 amount);

    /**
     * @notice Wraps underlying unit tokens into whitelabeled tokens for a specified owner
     * @dev Transfers `amount` of underlying unit tokens from the caller to this contract
     * and mints an equivalent amount of whitelabeled tokens to the `owner` address.
     * This maintains 1:1 parity between underlying units and whitelabeled tokens.
     * @param owner The address that will receive the minted whitelabeled tokens
     * @param amount The amount of underlying unit tokens to wrap and whitelabeled tokens to mint
     */
    function wrap(address owner, uint256 amount) external;

    /**
     * @notice Unwraps whitelabeled tokens back to underlying unit tokens
     * @dev Burns `amount` of whitelabeled tokens from the owner's balance
     * and transfers an equivalent amount of underlying unit tokens to the recipient.
     * This maintains the 1:1 parity in reverse direction.
     * If the caller is not the owner, the caller must have sufficient allowance to burn the owner's tokens.
     * @param owner The address that owns the whitelabeled tokens to be unwrapped
     * @param recipient The address that will receive the underlying unit tokens
     * @param amount The amount of whitelabeled tokens to burn and unit tokens to receive
     */
    function unwrap(address owner, address recipient, uint256 amount) external;

    /**
     * @notice Returns the address of the underlying Generic unit token that this contract wraps
     * @dev This is the ERC20 token address of the Generic units that back the whitelabeled tokens.
     * The underlying token typically represents claims on protocol vault positions and
     * may accrue yield over time through vault strategy operations.
     * @return The contract address of the underlying unit token
     */
    function genericUnit() external view returns (address);
}
