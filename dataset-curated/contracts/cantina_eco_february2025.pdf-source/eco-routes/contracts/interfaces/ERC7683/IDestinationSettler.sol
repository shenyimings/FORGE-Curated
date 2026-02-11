/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IDestinationSettler
 * @notice Standard interface for settlement contracts on the destination chain
 */
interface IDestinationSettler {
    /**
     * @notice Emitted when an intent is fulfilled
     * @param _orderId Hash of the fulfilled intent
     * @param _solver Address that fulfilled intent
     */
    event OrderFilled(bytes32 _orderId, address _solver);

    /// @notice Thrown when attempting to fill an order after the fill deadline has passed
    error FillDeadlinePassed();

    /**
     * @notice Fills a single leg of a particular order on the destination chain
     * @dev This method has been made payable, in contrast to original interface
     * @param orderId Unique order identifier for this order
     * @param originData Data emitted on the origin to parameterize the fill
     * @param fillerData Data provided by the filler to inform the fill or express their preferences
     */
    function fill(
        bytes32 orderId,
        bytes calldata originData,
        bytes calldata fillerData
    ) external payable;
}
