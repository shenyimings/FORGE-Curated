/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDestinationSettler} from "../interfaces/ERC7683/IDestinationSettler.sol";
import {Route} from "../types/Intent.sol";

/**
 * @title DestinationSettler
 * @notice Abstract contract implementing ERC-7683 destination chain settlement for Eco Protocol
 * @dev Handles intent fulfillment on destination chains through the ERC-7683 standard interface
 */
abstract contract DestinationSettler is IDestinationSettler {
    /**
     * @notice Fills a single leg of a particular order on the destination chain
     * @dev originData is of type OnchainCrossChainOrder
     * @dev fillerData is encoded bytes consisting of the claimant address and any additional data required for the chosen prover
     * @param orderId Unique identifier for the order being filled
     * @param originData Data emitted on the origin chain to parameterize the fill, equivalent to the originData field from the fillInstruction of the ResolvedCrossChainOrder. An encoded Intent struct.
     * @param fillerData Data provided by the filler to inform the fill or express their preferences
     */
    function fill(
        bytes32 orderId,
        bytes calldata originData,
        bytes calldata fillerData
    ) external payable {
        (bytes memory encodedRoute, bytes32 rewardHash) = abi.decode(
            originData,
            (bytes, bytes32)
        );

        emit OrderFilled(orderId, msg.sender);

        (
            address prover,
            uint64 source,
            bytes32 claimant,
            bytes memory proverData
        ) = abi.decode(fillerData, (address, uint64, bytes32, bytes));

        fulfillAndProve(
            orderId,
            abi.decode(encodedRoute, (Route)),
            rewardHash,
            claimant,
            prover,
            source,
            proverData
        );
    }

    /**
     * @notice Fulfills an intent and initiates proving in one transaction
     * @dev Abstract function to be implemented by concrete settlement contracts
     * @param intentHash The hash of the intent to fulfill
     * @param route The route information for the intent
     * @param rewardHash The hash of the reward details
     * @param claimant Cross-VM compatible claimant identifier
     * @param prover Address of prover on the destination chain
     * @param source The source chain ID where the intent was created
     * @param data Additional data for message formatting
     * @return Array of execution results from intent calls
     */
    function fulfillAndProve(
        bytes32 intentHash,
        Route memory route,
        bytes32 rewardHash,
        bytes32 claimant,
        address prover,
        uint64 source,
        bytes memory data
    ) public payable virtual returns (bytes[] memory);
}
