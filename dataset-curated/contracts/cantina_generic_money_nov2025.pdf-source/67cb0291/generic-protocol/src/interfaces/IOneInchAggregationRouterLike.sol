// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IOneInchAggregationRouterLike
 * @notice Interface for interacting with 1inch Aggregation Router contracts
 * @dev This interface defines the essential functions and data structures needed
 * to interact with 1inch protocol for token swapping operations
 */
interface IOneInchAggregationRouterLike {
    /**
     * @notice Parameters that describe a token swap operation
     * @param srcToken The address of the source token to be swapped
     * @param dstToken The address of the destination token to receive
     * @param srcReceiver The address that will receive any leftover source tokens
     * @param dstReceiver The address that will receive the swapped destination tokens
     * @param amount The amount of source tokens to swap
     * @param minReturnAmount The minimum amount of destination tokens expected
     * @param flags Configuration flags that control various swap options and behaviors
     */
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    /**
     * @notice Executes a token swap through the 1inch aggregation protocol
     * @dev This function performs the actual token swap using the provided parameters
     * and swap data. It supports complex multi-hop swaps and various DEX protocols.
     * @param executor The address authorized to execute the swap operation
     * @param desc The swap description containing all swap parameters
     * @param data Additional swap execution data required by the specific swap route
     * @return returnAmount The actual amount of destination tokens received
     * @return spentAmount The actual amount of source tokens consumed in the swap
     */
    function swap(
        address executor,
        SwapDescription calldata desc,
        bytes calldata data
    )
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount);
}
