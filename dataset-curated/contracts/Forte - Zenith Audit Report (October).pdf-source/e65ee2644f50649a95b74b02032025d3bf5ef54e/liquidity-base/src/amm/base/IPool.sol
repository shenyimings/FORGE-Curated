// SPDX-License-Identifier: BUSL-1.1
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
     * @param _minOut the amount of the other token in the pair minimum to be received for the_amountIn of _tokenIn.
     * @param _recipient address to receive tokens out
     * @param _expires timestamp at which the swap transaction will expire
     * @return amountOut the actual amount of the token coming out of the Pool as result of the swap
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     */
    function swap(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _minOut,
        address _recipient,
        uint256 _expires
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
    function xToken() external view returns (address);

    /**
     * @dev A function to get the address of the Y token of the pool.
     * @return the address of the Y token of the pool
     * @notice this value is immutable
     */
    function yToken() external view returns (address);

    /**
     * @dev This is the function to activate/deactivate trading.
     * @param _enable pass True to enable or False to disable
     */
    function enableSwaps(bool _enable) external;

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
     * @param recipient address to send the revenue to
     * @return revenue the normalized amount of revenue actually withdrawn
     */
    function withdrawRevenue(uint256 tokenId, uint256 Q, address recipient) external returns (uint256 revenue);

    /**
     * @dev This function collects the protocol fees from the Pool.
     * @param _recipient address that receives the fees
     */
    function collectProtocolFees(address _recipient) external;

    /**
     * @dev fee percentage for swaps for the LPs and for the protocol
     * @return lpFee the percentage for swaps in basis points that will go towards the LPs
     * @return protocolFee the percentage for swaps in basis points that will go towards the protocol
     * @return protocolFeeCollector address of the account with the privilage of collecting the the protocol fees
     * @return proposedProtocolFeeCollector the address proposed to be the new protocolFeeCollector
     * @return collectedProtocolFees the available amount of protocol fees to be collected
     */
    function getFeeInfo()
        external
        view
        returns (
            uint16 lpFee,
            uint16 protocolFee,
            address protocolFeeCollector,
            address proposedProtocolFeeCollector,
            uint256 collectedProtocolFees
        );

    /**
     * @dev returns the current total liquidity in the Pool
     * @return w
     */
    function w() external returns (uint256);

    /**
     * @dev This is the function to get the revenue available for a liquidity position.
     * @param tokenId The tokenId representing the liquidity position
     * @return _revenueAvailable The amount of revenue available for the liquidity position
     */
    function revenueAvailable(uint256 tokenId) external view returns (uint256);
}
