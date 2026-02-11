/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../types/ERC7683.sol";

/**
 * @title IOriginSettler
 * @notice Standard interface for settlement contracts on the origin chain
 */

interface IOriginSettler {
    /// @notice Thrown when the sent native token amount is less than the required reward amount
    error InsufficientNativeReward();

    /// @notice Thrown when data type signature does not match the expected value
    error TypeSignatureMismatch();

    /// @notice Thrown when the source chain's chainID does not match the expected value
    error OriginChainIDMismatch();

    /// @notice Thrown when attempting to open an order after the open deadline has passed
    error OpenDeadlinePassed();

    /// @notice Thrown when signature does not match the expected value
    error BadSignature();

    /**
     * @notice Signals that an order has been opened
     * @param orderId a unique order identifier within this settlement system
     * @param resolvedOrder resolved order that would be returned by resolve if called instead of Open
     */
    event Open(bytes32 indexed orderId, ResolvedCrossChainOrder resolvedOrder);

    /**
     * @notice Opens a cross-chain order
     * @dev To be called by the user
     * @dev This method must emit the Open event
     * @dev This method has been made payable, in contrast to original interface
     * @param order The OnchainCrossChainOrder definition
     */
    function open(OnchainCrossChainOrder calldata order) external payable;

    /**
     * @notice Opens a gasless cross-chain order on behalf of a user.
     * @dev To be called by the filler.
     * @dev This method must emit the Open event
     * @dev This method has been made payable, in contrast to original interface
     * @param order The GaslessCrossChainOrder definition
     * @param signature The user's signature over the order
     * @param originFillerData Any filler-defined data required by the settler
     */
    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata originFillerData
    ) external payable;

    /**
     * @notice Resolves a specific GaslessCrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order The GaslessCrossChainOrder definition
     * @param originFillerData Any filler-defined data required by the settler
     * @return ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata originFillerData
    ) external view returns (ResolvedCrossChainOrder memory);

    /**
     * @notice Resolves a specific OnchainCrossChainOrder into a generic ResolvedCrossChainOrder
     * @dev Intended to improve standardized integration of various order types and settlement contracts
     * @param order The OnchainCrossChainOrder definition
     * @return ResolvedCrossChainOrder hydrated order data including the inputs and outputs of the order
     */
    function resolve(
        OnchainCrossChainOrder calldata order
    ) external view returns (ResolvedCrossChainOrder memory);
}
