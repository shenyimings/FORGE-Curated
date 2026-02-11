// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC7575Share } from "./IERC7575Share.sol";
import { IERC20Mintable } from "./IERC20Mintable.sol";

/**
 * @title IGenericShare Interface
 * @notice Interface for the share token with controlled minting and burning capabilities.
 * @dev This interface extends ERC20 functionality to include administrative functions for token
 * supply management with proper access control. The share token is an ERC20-compliant token
 * that serves as a synthetic asset backed by multiple stablecoin vaults.
 *
 * Key Features:
 * - ERC20 compliance for standard token operations
 * - Controlled minting and burning functionality with owner access control
 *
 * Access Control:
 * - mint(): Only owner
 * - burn(): Only owner
 * - ERC20 operations: All users
 */
interface IGenericShare is IERC20Mintable, IERC7575Share { }
