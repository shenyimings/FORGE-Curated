// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IPermit } from "./interfaces/IPermit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
     * Maps: owner => tokenAddress32 => spender => {amount, expiration, timestamp}
     */
    mapping(address => mapping(bytes32 => mapping(address => Allowance))) internal allowances;

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
        bytes32 tokenKey = bytes32(uint256(uint160(token)));
        Allowance memory allowed = allowances[user][tokenKey][spender];
        return (allowed.amount, allowed.expiration, allowed.timestamp);
    }

    /**
     * @notice Internal function to validate approval parameters and check for locked allowances
     * @param owner Token owner address
     * @param tokenKey Token identifier key
     * @param token Token contract address
     * @param spender Spender address
     * @param expiration Expiration timestamp
     */
    function _validateApproval(
        address owner,
        bytes32 tokenKey,
        address token,
        address spender,
        uint48 expiration
    ) internal view {
        // Check if allowance is locked
        if (allowances[owner][tokenKey][spender].expiration == LOCKED_ALLOWANCE) {
            revert AllowanceLocked(owner, tokenKey, spender);
        }

        // Validate parameters
        if (token == address(0)) {
            revert ZeroToken();
        }
        if (spender == address(0)) {
            revert ZeroSpender();
        }
        if (expiration != 0 && expiration <= block.timestamp) {
            revert InvalidExpiration(expiration);
        }
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
        bytes32 tokenKey = bytes32(uint256(uint160(token)));
        _validateApproval(msg.sender, tokenKey, token, spender, expiration);

        allowances[msg.sender][tokenKey][spender] =
            Allowance({ amount: amount, expiration: expiration, timestamp: uint48(block.timestamp) });

        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    /**
     * @notice Execute approved token transfer
     * @dev Checks allowance and expiration before transfer using _updateAllowance helper
     * @param from Token owner address
     * @param to Transfer recipient address
     * @param amount Transfer amount (max 2^160-1)
     * @param token ERC20 token contract address
     */
    function transferFrom(address from, address to, uint160 amount, address token) public {
        bytes32 tokenKey = bytes32(uint256(uint160(token)));
        (, bytes memory revertData) = _updateAllowance(from, tokenKey, msg.sender, amount);
        if (revertData.length > 0) {
            _revert(revertData);
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

            bytes32 tokenKey = bytes32(uint256(uint160(token)));
            allowances[msg.sender][tokenKey][spender] =
                Allowance({ amount: 0, expiration: LOCKED_ALLOWANCE, timestamp: uint48(block.timestamp) });

            emit Lockdown(msg.sender, token, spender);
        }
    }

    /**
     * @dev Internal helper function to revert with custom error data
     * @dev Uses inline assembly to revert with the exact error from revertData
     * @param revertData The ABI-encoded error data to revert with
     */
    function _revert(
        bytes memory revertData
    ) internal pure {
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }

    /**
     * @notice Updates allowance after checking validity and sufficiency
     * @dev Internal helper that validates lock status, expiration, and sufficient balance
     * @dev Returns error data instead of reverting to allow fallback mechanisms
     * @param from Token owner address
     * @param tokenKey Bytes32 token key for allowance mapping
     * @param spender Approved spender address
     * @param amount Amount to deduct from allowance
     * @return allowed Updated allowance struct after deduction
     * @return revertData Encoded error data if validation fails, empty bytes if successful
     */
    function _updateAllowance(
        address from,
        bytes32 tokenKey,
        address spender,
        uint160 amount
    ) internal returns (Allowance memory allowed, bytes memory revertData) {
        allowed = allowances[from][tokenKey][spender];

        if (allowed.expiration == LOCKED_ALLOWANCE) {
            revertData = abi.encodeWithSelector(AllowanceLocked.selector, from, tokenKey, spender);
            return (allowed, revertData);
        }

        if (allowed.expiration != 0 && block.timestamp > allowed.expiration) {
            revertData = abi.encodeWithSelector(AllowanceExpired.selector, allowed.expiration);
            return (allowed, revertData);
        }

        if (allowed.amount == MAX_ALLOWANCE) {
            return (allowed, revertData);
        }

        if (allowed.amount < amount) {
            revertData = abi.encodeWithSelector(InsufficientAllowance.selector, amount, allowed.amount);
            return (allowed, revertData);
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

        allowances[from][tokenKey][spender] = allowed;
    }

    /**
     * @dev Execute ERC20 token transfer with safety checks using SafeERC20
     * @dev Uses SafeERC20.safeTransferFrom to handle non-standard token implementations
     * @param from Token sender address that must have approved this contract
     * @param to Token recipient address that will receive the tokens
     * @param amount Transfer amount in token units (max uint160)
     * @param token ERC20 token contract address to transfer
     * @notice This function handles tokens that don't return boolean values or return false on failure
     * @notice Assumes the caller has already verified allowances and will revert on transfer failure
     */
    function _transferFrom(address from, address to, uint160 amount, address token) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
