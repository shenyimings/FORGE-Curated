/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../types/ERC7683.sol";

/**
 * @title IOriginSettler
 * @notice Standard interface for settlement contracts on the origin chain
 * @dev Updated interface supporting enhanced validation, replay protection, and ERC-7683 compliance
 */
interface IOriginSettler {
    /// @notice Thrown when the sent native token amount is less than the required reward amount
    error InsufficientNativeRewardAmount();

    /// @notice Thrown when data type signature does not match the expected value
    error TypeSignatureMismatch();

    /// @notice Thrown when the origin chain ID in the order does not match the current chain
    error InvalidOriginChainId(uint256 expected, uint256 actual);

    /// @notice Thrown when attempting to open an order after the open deadline has passed
    error OpenDeadlinePassed();

    /// @notice Thrown when the provided signature is invalid or does not match the order
    error InvalidSignature();

    /// @notice Thrown when the origin settler address in the order does not match this contract
    error InvalidOriginSettler(address expected, address actual);

    /**
     * @notice Signals that an order has been opened
     * @param orderId a unique order identifier within this settlement system
     * @param resolvedOrder resolved order that would be returned by resolve if called instead of Open
     */
    event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);

    /**
     * @notice Opens a cross-chain order directly by the user
     * @dev Called by the user to create and fund an intent
     * @dev Validates order data type and handles intent funding
     * @dev Emits Open event with resolved order data
     * @dev Made payable to support native token rewards
     * @param order The OnchainCrossChainOrder definition with embedded OrderData
     */
    function open(OnchainCrossChainOrder calldata order) external payable;

    /**
     * @notice Opens a gasless cross-chain order on behalf of a user
     * @dev Called by a solver to create an intent for a user via signature
     * @dev Validates signature, deadlines, chain IDs, and origin settler address
     * @dev Includes replay protection through vault state checking
     * @dev Emits Open event with resolved order data
     * @dev Made payable to support native token rewards
     * @param order The GaslessCrossChainOrder definition with user signature
     * @param signature The user's EIP-712 signature authorizing the order
     * @param originFillerData Any filler-defined data (currently unused)
     */
    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata originFillerData
    ) external payable;

    /**
     * @notice Resolves a gasless order into ERC-7683 compliant ResolvedCrossChainOrder
     * @dev Converts OrderData to standardized format for off-chain solvers
     * @dev Uses orderData.maxSpent directly and corrects chainId assignments
     * @dev FillInstruction.originData contains (route, rewardHash) not full intent
     * @param order The GaslessCrossChainOrder definition with embedded OrderData
     * @param originFillerData Any filler-defined data (currently unused)
     * @return ResolvedCrossChainOrder ERC-7683 compliant order with proper field mappings
     */
    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata originFillerData
    ) external view returns (ResolvedCrossChainOrder memory);

    /**
     * @notice Resolves an onchain order into ERC-7683 compliant ResolvedCrossChainOrder
     * @dev Converts OrderData to standardized format for off-chain solvers
     * @dev Uses orderData.maxSpent directly and corrects chainId assignments
     * @dev FillInstruction.originData contains (route, rewardHash) not full intent
     * @param order The OnchainCrossChainOrder definition with embedded OrderData
     * @return ResolvedCrossChainOrder ERC-7683 compliant order with proper field mappings
     */
    function resolve(
        OnchainCrossChainOrder calldata order
    ) external view returns (ResolvedCrossChainOrder memory);
}
