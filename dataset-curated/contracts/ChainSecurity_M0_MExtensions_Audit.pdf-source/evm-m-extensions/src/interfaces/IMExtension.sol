// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

/**
 * @title  M Extension interface extending Extended ERC20,
 *         includes additional enable/disable earnings and index logic.
 * @author M0 Labs
 */
interface IMExtension is IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when M extension earning is enabled.
     * @param  index The index at the moment earning is enabled.
     */
    event EarningEnabled(uint128 index);

    /**
     * @notice Emitted when M extension earning is disabled.
     * @param  index The index at the moment earning is disabled.
     */
    event EarningDisabled(uint128 index);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when performing an operation that is not allowed when earning is disabled.
    error EarningIsDisabled();

    /// @notice Emitted when performing an operation that is not allowed when earning is enabled.
    error EarningIsEnabled();

    /**
     * @notice Emitted when there is insufficient balance to decrement from `account`.
     * @param  account The account with insufficient balance.
     * @param  balance The balance of the account.
     * @param  amount  The amount to decrement.
     */
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /// @notice Emitted in constructor if M Token is 0x0.
    error ZeroMToken();

    /// @notice Emitted in constructor if Swap Facility is 0x0.
    error ZeroSwapFacility();

    /// @notice Emitted in `wrap` and `unwrap` functions if the caller is not the Swap Facility.
    error NotSwapFacility();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Enables earning of extension token if allowed by the TTG Registrar and if it has never been done.
     * @dev SHOULD be virtual to allow extensions to override it.
     */
    function enableEarning() external;

    /**
     * @notice Disables earning of extension token if disallowed by the TTG Registrar and if it has never been done.
     * @dev SHOULD be virtual to allow extensions to override it.
     */
    function disableEarning() external;

    /**
     * @notice Wraps `amount` M from the caller into extension token for `recipient`.
     * @dev    Can only be called by the SwapFacility.
     * @param  recipient The account receiving the minted M extension token.
     * @param  amount    The amount of M extension token minted.
     */
    function wrap(address recipient, uint256 amount) external;

    /**
     * @notice Unwraps `amount` extension token from the caller into M for `recipient`.
     * @dev    Can only be called by the SwapFacility.
     * @param  recipient The account receiving the withdrawn M,
     *         it will always be the SwapFacility (keep `recipient` for backward compatibility).
     * @param  amount    The amount of M extension token burned.
     */
    function unwrap(address recipient, uint256 amount) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the M Token contract.
    function mToken() external view returns (address);

    /// @notice The address of the SwapFacility contract.
    function swapFacility() external view returns (address);

    /**
     * @notice Whether M extension earning is enabled.
     * @dev SHOULD be virtual to allow extensions to override it.
     */
    function isEarningEnabled() external view returns (bool);

    /**
     * @notice Returns the current index for M extension earnings.
     * @dev SHOULD be virtual to allow extensions to override it.
     */
    function currentIndex() external view returns (uint128);
}
