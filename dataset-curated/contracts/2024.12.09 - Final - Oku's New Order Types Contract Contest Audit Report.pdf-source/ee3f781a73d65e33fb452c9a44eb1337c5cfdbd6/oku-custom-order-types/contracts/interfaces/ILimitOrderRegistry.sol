// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./uniswapV3/UniswapV3Pool.sol";
import "./openzeppelin/ERC20.sol";
import "./chainlink/AutomationCompatibleInterface.sol";

interface ILimitOrderRegistry is AutomationCompatibleInterface {
    /**
     * @notice The minimum amount of assets required to create a `newOrder`.
     * @dev Changeable by owner.
     */
    function minimumAssets(ERC20 asset) external view returns (uint256 min);

    /**
     * @notice Stores linked list center values, and frequently used pool values.
     * @param centerHead Linked list center value closer to head of the list
     * @param centerTail Linked list center value closer to tail of the list
     * @param token0 ERC20 token0 of the pool
     * @param token1 ERC20 token1 of the pool
     * @param fee Uniswap V3 pool fee
     */
    struct PoolData {
        uint256 centerHead;
        uint256 centerTail;
        ERC20 token0;
        ERC20 token1;
        uint24 fee;
    }
    function poolToData(
        UniswapV3Pool pool
    ) external view returns (PoolData memory data);

    /**
     * @notice Users can claim fulfilled orders by passing in the `batchId` corresponding to the order they want to claim.
     * @param batchId the batchId corresponding to a fulfilled order to claim
     * @param user the address of the user in the order to claim for
     * @return address erc20 address
     * @return uint256 amount claimed
     * @dev Caller must either approve this contract to spend their Wrapped Native token, and have at least `getFeePerUser` tokens in their wallet.
     *      Or caller must send `getFeePerUser` value with this call.
     */
    function claimOrder(
        uint128 batchId,
        address user
    ) external payable returns (ERC20, uint256);

    /**
     * @notice Allows users to cancel orders as long as they are completely OTM.
     * @param pool the Uniswap V3 pool that contains the limit order to cancel
     * @param targetTick the targetTick of the order you want to cancel
     * @param direction bool indication the direction of the order
     * @return amount0 amount0 withdrawn
     * @return amount1 amount1 withdrawn
     * @return batchId batch id withdrawn
     */
    function cancelOrder(
        UniswapV3Pool pool,
        int24 targetTick,
        bool direction,
        uint256 deadline
    ) external returns (uint128 amount0, uint128 amount1, uint128 batchId);

    /**
     * @notice Creates a new limit order for a specific pool.
     * @dev Limit orders can be created to buy either token0, or token1 of the pool.
     * @param pool the Uniswap V3 pool to create a limit order on.
     * @param targetTick the tick, that when `pool`'s tick passes, the order will be completely fulfilled
     * @param amount the amount of the input token to sell for the desired token out
     * @param direction bool indicating what the desired token out is
     *                  - true  token in = token0 ; token out = token1
     *                  - false token in = token1 ; token out = token0
     * @param startingNode an NFT position id indicating where this contract should start searching for a spot in the list
     *                     - can be zero which defaults to starting the search at center of list
     * @dev reverts if
     *      - pool is not setup
     *      - targetTick is not divisible by the pools tick spacing
     *      - the new order would be ITM, or in a MIXED state
     *      - the new order does not meet minimum liquidity requirements
     *      - transferFrom fails

     * @dev Emits a `NewOrder` event which contains meta data about the order including the orders `batchId`(which is used for claiming/cancelling).
     */
    function newOrder(
        UniswapV3Pool pool,
        int24 targetTick,
        uint128 amount,
        bool direction,
        uint256 startingNode,
        uint256 deadline
    ) external returns (uint128);
}
