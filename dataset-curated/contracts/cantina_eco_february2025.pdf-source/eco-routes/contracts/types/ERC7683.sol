/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title GaslessCrossChainOrder CrossChainOrder type
 * @notice Standard order struct to be signed by users, disseminated to fillers, and submitted to origin settler contracts
 * @param originSettler The contract address that the order is meant to be settled by
 * Fillers send this order to this contract address on the origin chain
 * @param user The address of the user who is initiating the swap whose input tokens will be taken and escrowed
 * @param nonce Nonce to be used as replay protection for the order
 * @param originChainId The chainId of the origin chain
 * @param openDeadline The timestamp by which the order must be opened
 * @param fillDeadline The timestamp by which the order must be filled on the destination chain
 * @param orderDataType Type identifier for the order data. This is an EIP-712 typehash
 * @param orderData Arbitrary implementation-specific data
 * Can be used to define tokens, amounts, destination chains, fees, settlement parameters,
 * or any other order-type specific information
 */
struct GaslessCrossChainOrder {
    address originSettler;
    address user;
    uint256 nonce;
    uint256 originChainId;
    uint32 openDeadline;
    uint32 fillDeadline;
    bytes32 orderDataType;
    bytes orderData;
}
/**
 * @title OnchainCrossChainOrder CrossChainOrder type
 * @notice Standard order struct for user-opened orders, where the user is the msg.sender.
 * @param fillDeadline The timestamp by which the order must be filled on the destination chain
 * @param orderDataType Type identifier for the order data. This is an EIP-712 typehash
 * @param orderData Arbitrary implementation-specific data
 * Can be used to define tokens, amounts, destination chains, fees, settlement parameters,
 * or any other order-type specific information
 */
struct OnchainCrossChainOrder {
    uint32 fillDeadline;
    bytes32 orderDataType;
    bytes orderData;
}

/**
 * @title ResolvedCrossChainOrder type
 * @notice An implementation-generic representation of an order intended for filler consumption
 * @dev Defines all requirements for filling an order by unbundling the implementation-specific orderData.
 * @dev Intended to improve integration generalization by allowing fillers to compute the exact input and output information of any order
 * @param user The address of the user who is initiating the transfer
 * @param originChainId The chainId of the origin chain
 * @param openDeadline The timestamp by which the order must be opened
 * @param fillDeadline The timestamp by which the order must be filled on the destination chain(s)
 * @param orderId The unique identifier for this order within this settlement system
 * @param maxSpent The max outputs that the filler will send. It's possible the actual amount depends on the state of the destination
 * chain (destination dutch auction, for instance), so these outputs should be considered a cap on filler liabilities.
 * @param minReceived The minimum outputs that must be given to the filler as part of order settlement. Similar to maxSpent, it's possible
 * that special order types may not be able to guarantee the exact amount at open time, so this should be considered
 * a floor on filler receipts. Setting the `recipient` of an `Output` to address(0) indicates that the filler is not
 * known when creating this order.
 * @param fillInstructions Each instruction in this array is parameterizes a single leg of the fill. This provides the filler with the information
 * necessary to perform the fill on the destination(s).
 */
struct ResolvedCrossChainOrder {
    address user;
    uint256 originChainId;
    uint32 openDeadline;
    uint32 fillDeadline;
    bytes32 orderId;
    Output[] maxSpent;
    Output[] minReceived;
    FillInstruction[] fillInstructions;
}

/**
 * @title Output type
 * @notice Tokens that must be received for a valid order fulfillment
 * @param token The address of the ERC20 token on the destination chain
 * address(0) used as a sentinel for the native token
 * @param amount The amount of the token to be sent
 * @param recipient The address to receive the output tokens
 * @param chainId The destination chain for this output
 */
struct Output {
    bytes32 token;
    uint256 amount;
    bytes32 recipient;
    uint256 chainId;
}

/**
 * @title FillInstruction type
 * @notice Instructions to parameterize each leg of the fill
 * @dev Provides all the origin-generated information required to produce a valid fill leg
 * @param destinationChainId The chain ID that the order is meant to be settled by
 * @param destinationSettler The contract address that the order is meant to be filled on
 * @param originData The data generated on the origin chain needed by the destinationSettler to process the fill
 */
struct FillInstruction {
    uint64 destinationChainId;
    bytes32 destinationSettler;
    bytes originData;
}
