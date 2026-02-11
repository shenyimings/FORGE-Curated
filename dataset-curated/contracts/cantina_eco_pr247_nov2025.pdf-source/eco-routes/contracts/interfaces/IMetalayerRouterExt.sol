// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMetalayerRouter} from "@metalayer/contracts/src/interfaces/IMetalayerRouter.sol";

/**
 * @title IMetalayerRouterExt
 * @notice Extended interface for MetalayerRouter with additional quoteDispatch function
 * @dev Extends base interface to expose 4-parameter quoteDispatch that accepts custom hook metadata.
 *      The base IMetalayerRouter only exposes 3-parameter version with hardcoded 100k gas limit.
 */
interface IMetalayerRouterExt is IMetalayerRouter {
    /**
     * @notice Computes quote for dispatching a message with custom hook metadata
     * @dev This function allows specifying custom gas limits via hook metadata,
     *      fixing the hardcoded 100k gas limit issue in the 3-parameter version
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @param defaultHookMetadata Metadata used by the default post dispatch hook (contains gas limit)
     * @return fee The payment required to dispatch the message
     */
    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes memory defaultHookMetadata
    ) external view returns (uint256 fee);
}
