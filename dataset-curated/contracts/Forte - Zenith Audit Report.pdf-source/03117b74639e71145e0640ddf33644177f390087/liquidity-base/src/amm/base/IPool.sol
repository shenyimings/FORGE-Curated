// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolEvents} from "../../common/IEvents.sol";

/**
 * @title IPool Interface
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 * @dev function signatures for all Pools
 */

interface IPool is IPoolEvents {
    /**
     * @dev This is the main function of the pool to swap.
     * @param _tokenIn the address of the token being given to the pool in exchange for another token
     * @param _amountIn the amount of the ERC20 _tokenIn to exchange into the Pool
     * @param _minOut the amount of the other token in the pair minimum to be received for the
     * _amountIn of _tokenIn.
     * @return amountOut the actual amount of the token coming out of the Pool as result of the swap
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     */
    function swap(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _minOut
    ) external returns (uint256 amountOut, uint256 lpFeeAmount, uint256 protocolFeeAmount);

    /**
     * @dev This is the function to retrieve the current spot price of the x token.
     * @return sPrice the price in YToken Decimals
     */
    function spotPrice() external returns (uint256 sPrice);

    /**
     * @dev This is a simulation of the swap function. Useful to get marginal price.
     * @param _tokenIn the address of the token being sold
     * @param _amountIn the amount of the ERC20 _tokenIn to sell to the Pool
     * @return amountOut the amount of the token coming out of the Pool as result of the swap (main returned value)
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     */
    function simSwap(
        address _tokenIn,
        uint256 _amountIn
    ) external returns (uint256 amountOut, uint256 lpFeeAmount, uint256 protocolFeeAmount);

    /**
     * @dev This is a simulation of the swap function from the perspective of purchasing a specific amount. Useful to get marginal price.
     * @param _tokenout the address of the token being bought
     * @param _amountOut the amount of the ERC20 _tokenOut to buy from the Pool
     * @return amountIn the amount necessary of the token coming into the Pool for the desired amountOut of the swap (main returned value)
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     * @notice lpFeeAmount and protocolFeeAmount are already factored in the amountIn. This is useful only to know how much of the amountIn
     * will go towards fees.
     */
    function simSwapReversed(
        address _tokenout,
        uint256 _amountOut
    ) external returns (uint256 amountIn, uint256 lpFeeAmount, uint256 protocolFeeAmount);

    /**
     * @dev A function to get the address of the x token of the pool.
     * @return the address of the x token of the pool
     * @notice this value is immutable
     */
    function xToken() external returns (address);

    /**
     * @dev A function to get the address of the Y token of the pool.
     * @return the address of the Y token of the pool
     * @notice this value is immutable
     */
    function yToken() external returns (address);

    /**
     * @dev This is the function to activate/deactivate trading.
     * @param _enable pass True to enable or False to disable
     */
    function enableSwaps(bool _enable) external;

    /**
     * @dev This is the function to add XToken liquidity to the pool.
     * @param _amount the amount of X token to transfer from the sender to the pool
     */
    function addXSupply(uint256 _amount) external;

    /**
     * @dev This is the function to update the LP fees per trading.
     * @param _fee percentage of the transaction that will get collected as fees (in percentage basis points:
     * 10000 -> 100.00%; 500 -> 5.00%; 1 -> 0.01%)
     */
    function setLPFee(uint16 _fee) external;

    /**
     * @dev This is the function to update the protocol fees per trading.
     * @param _protocolFee percentage of the transaction that will get collected as fees (in percentage basis points:
     * 10000 -> 100.00%; 500 -> 5.00%; 1 -> 0.01%)
     */
    function setProtocolFee(uint16 _protocolFee) external;

    /**
     * @dev function to propose a new protocol fee collector
     * @param _protocolFeeCollector the new fee collector
     * @notice that only the current fee collector address can call this function
     */
    function proposeProtocolFeeCollector(address _protocolFeeCollector) external;

    /**
     * @dev function to confirm a new protocol fee collector
     * @notice that only the already proposed fee collector can call this function
     */
    function confirmProtocolFeeCollector() external;

    /**
     * @dev This function allows the owner of the lp token to pull accrued revenue from the Pool.
     * @param tokenId the id of the LP token to withdraw revenue for
     * @param Q the amount of revenue to withdraw
     * @return revenue the normalized amount of revenue actually withdrawn
     */
    function withdrawRevenue(uint256 tokenId, uint256 Q) external returns (uint256 revenue);

    /**
     * @dev This function collects the protocol fees from the Pool.
     */
    function collectProtocolFees() external;

    /**
     * @dev This function gets the liquidity in the pool for xToken in WAD.
     * @return the liquidity in the pool for xToken in WAD
     */
    function xTokenLiquidity() external returns (uint256);

    /**
     * @dev This function gets the liquidity in the pool for yToken in WAD
     * @return the liquidity in the pool for yToken in WAD
     */
    function yTokenLiquidity() external returns (uint256);

    /**
     * @dev fee percentage for swaps for the LP
     * @return the percentage for swaps in basis points that will go towards the LP
     */
    function lpFee() external returns (uint16);

    /**
     * @dev fee percentage for swaps for the protocol
     * @return the percentage for swaps in basis points that will go towards the protocol
     */
    function protocolFee() external returns (uint16);

    /**
     * @dev protocol-fee collector address
     * @return the current protocolFeeCollector address
     */
    function protocolFeeCollector() external returns (address);

    /**
     * @dev proposed protocol-fee collector address
     * @return the current proposedProtocolFeeCollector address
     */
    function proposedProtocolFeeCollector() external returns (address);

    /**
     * @dev tells current LP fees accumulated in the pool
     * @return currently claimable LP fee balance
     */
    function collectedLPFees() external returns (uint256);

    /**
     * @dev tells current protocol fees accumulated in the pool
     * @return currently claimable protocol fee balance
     */
    function collectedProtocolFees() external returns (uint256);

    /**
     * @dev This function returns the available revenue for the given token
     * @param lp The address of the liquidity provider
     * @param tokenId The ID of the LPToken
     * @return uint256 amount of revenue available for the given token
     */
    function revenueAvailable(address lp, uint256 tokenId) external returns (uint256);

    /**
     * @dev returns the current total liquidity in the Pool
     * @return w
     */
    function w() external returns (uint256);
}
