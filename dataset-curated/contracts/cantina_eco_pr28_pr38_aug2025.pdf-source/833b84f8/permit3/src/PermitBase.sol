// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPermit } from "./interfaces/IPermit.sol";

/**
 * @title PermitBase
 * @notice Base implementation for token approvals and transfers
 * @dev Core functionality for managing token permissions
 */
contract PermitBase is IPermit {
    using SafeERC20 for IERC20;

    /// @dev Special value representing a locked allowance that cannot be used
    /// @dev Value of 2 is chosen to distinguish from 0 (no expiration) and 1 (expired)
    uint48 internal constant LOCKED_ALLOWANCE = 2;

    /// @dev Maximum value for uint160, representing unlimited/infinite allowance
    /// @dev Using uint160 instead of uint256 to save gas on storage operations
    uint160 internal constant MAX_ALLOWANCE = type(uint160).max;

    /**
     * @dev Core data structure for tracking token permissions
     * Maps: owner => token => spender => {amount, expiration, timestamp}
     */
    mapping(address => mapping(address => mapping(address => Allowance))) internal allowances;

    /**
     * @notice Query current token allowance
     * @dev Retrieves full allowance details including expiration
     * @param user Token owner
     * @param token ERC20 token address
     * @param spender Approved spender
     * @return amount Current approved amount
     * @return expiration Timestamp when approval expires
     * @return timestamp Timestamp when approval was set
     */
    function allowance(
        address user,
        address token,
        address spender
    ) external view returns (uint160 amount, uint48 expiration, uint48 timestamp) {
        Allowance memory allowed = allowances[user][token][spender];
        return (allowed.amount, allowed.expiration, allowed.timestamp);
    }

    /**
     * @notice Direct allowance approval without signature
     * @dev Alternative to permit() for simple approvals
     * @param token ERC20 token address
     * @param spender Address to approve
     * @param amount Approval amount
     * @param expiration Optional expiration timestamp
     */
    function approve(address token, address spender, uint160 amount, uint48 expiration) external override {
        // Prevent overriding locked allowances
        if (allowances[msg.sender][token][spender].expiration == LOCKED_ALLOWANCE) {
            revert AllowanceLocked(msg.sender, token, spender);
        }

        if (token == address(0)) {
            revert ZeroToken();
        }
        if (spender == address(0)) {
            revert ZeroSpender();
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        if (expiration != 0 && expiration <= block.timestamp) {
            revert InvalidExpiration(expiration);
        }

        allowances[msg.sender][token][spender] =
            Allowance({ amount: amount, expiration: expiration, timestamp: uint48(block.timestamp) });

        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    /**
     * @notice Execute approved token transfer
     * @dev Checks allowance and expiration before transfer
     * @param from Token owner
     * @param token ERC20 token address
     * @param to Transfer recipient
     * @param amount Transfer amount
     */
    function transferFrom(address from, address to, uint160 amount, address token) public {
        if (from == address(0)) {
            revert ZeroFrom();
        }
        if (token == address(0)) {
            revert ZeroToken();
        }
        if (to == address(0)) {
            revert ZeroTo();
        }

        Allowance memory allowed = allowances[from][token][msg.sender];

        if (allowed.expiration == LOCKED_ALLOWANCE) {
            revert AllowanceLocked(from, token, msg.sender);
        }

        if (allowed.expiration != 0 && block.timestamp > allowed.expiration) {
            revert AllowanceExpired(allowed.expiration);
        }

        if (allowed.amount != MAX_ALLOWANCE) {
            if (allowed.amount < amount) {
                revert InsufficientAllowance(amount, allowed.amount);
            }
            /**
             * @dev SAFETY: This unchecked block is safe from underflow because:
             * 1. The require statement immediately above guarantees that allowed.amount >= amount
             * 2. When subtracting amount from allowed.amount, the result will always be >= 0
             * 3. Both allowed.amount and amount are uint160 types, ensuring type consistency
             * 4. The subtraction can never underflow since we've verified the allowance is sufficient
             *
             * This optimization saves gas by avoiding redundant underflow checks that Solidity
             * would normally perform, since we've already validated the operation will succeed.
             */
            unchecked {
                allowed.amount -= amount;
            }

            allowances[from][token][msg.sender] = allowed;
        }

        _transferFrom(from, to, amount, token);
    }

    /**
     * @notice Execute multiple approved transfers
     * @dev Batch version of transferFrom()
     * @param transfers Array of transfer instructions
     */
    function transferFrom(
        AllowanceTransferDetails[] calldata transfers
    ) external {
        uint256 transfersLength = transfers.length;
        if (transfersLength == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < transfersLength; i++) {
            transferFrom(transfers[i].from, transfers[i].to, transfers[i].amount, transfers[i].token);
        }
    }

    /**
     * @notice Revoke multiple token approvals
     * @dev Emergency function to quickly remove permissions
     * @param approvals Array of token-spender pairs to revoke
     */
    function lockdown(
        TokenSpenderPair[] calldata approvals
    ) external {
        uint256 approvalsLength = approvals.length;
        if (approvalsLength == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < approvalsLength; i++) {
            address token = approvals[i].token;
            address spender = approvals[i].spender;

            if (token == address(0)) {
                revert ZeroToken();
            }
            if (spender == address(0)) {
                revert ZeroSpender();
            }

            allowances[msg.sender][token][spender] =
                Allowance({ amount: 0, expiration: LOCKED_ALLOWANCE, timestamp: uint48(block.timestamp) });

            emit Lockdown(msg.sender, token, spender);
        }
    }

    /**
     * @dev Execute token transfer with safety checks using SafeERC20
     * @param from Token sender address that must have approved this contract
     * @param token ERC20 token contract address to transfer
     * @param to Token recipient address that will receive the tokens
     * @param amount Transfer amount in token units (max uint160)
     * @notice This function uses SafeERC20.safeTransferFrom to handle tokens that:
     *         - Don't return a boolean value
     *         - Return false on failure instead of reverting
     *         - Have other non-standard transfer implementations
     * @notice The function assumes the caller has already verified allowances
     *         and will revert if the transfer fails for any reason
     */
    function _transferFrom(address from, address to, uint160 amount, address token) internal {
        if (from == address(0)) {
            revert ZeroFrom();
        }
        if (token == address(0)) {
            revert ZeroToken();
        }
        if (to == address(0)) {
            revert ZeroTo();
        }

        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
