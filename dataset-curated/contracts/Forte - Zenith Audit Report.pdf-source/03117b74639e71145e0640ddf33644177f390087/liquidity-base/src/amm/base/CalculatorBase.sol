// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../common/IErrors.sol";
import {Constants} from "../../common/Constants.sol";
import {packedFloat} from "../mathLibs/MathLibs.sol";

/**
 * @title Calculator Base Abstract Contract
 * @dev This contract serves as the base for all the calculators.
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

abstract contract CalculatorBase is Constants {
    /**
     * @dev This is the function to retrieve the current spot price of the x token.
     * @return sPrice the price in YToken Decimals
     */
    function _spotPrice() internal view virtual returns (packedFloat sPrice);

    /**
     * @dev This function updates the state of the math values of the pool.
     * @param x_old the previous tracker for x
     */
    function _updateParameters(packedFloat x_old) public virtual;

    /**
     * @dev This function calculates the amount of token X required for the user to purchase a specific amount of Token Y (buy y with x : out perspective).
     * @param _amountOfY desired amount of token Y
     */
    function _calculateAmountOfXRequiredBuyingY(
        packedFloat _amountOfY
    ) internal view virtual returns (packedFloat amountOfX);

    /**
     * @dev This function calculates the amount of token Y required for the user to purchase a specific amount of Token X (buy x with y : out perspective).
     * @param _amountOfX desired amount of token X
     * @return amountOfY required amount of token Y
     */
    function _calculateAmountOfYRequiredBuyingX(
        packedFloat _amountOfX
    ) internal view virtual returns (packedFloat amountOfY);

    /**
     * @dev This function calculates the amount of token Y the user will receive when selling token X (sell x for y : in perspective).
     * @param _amountOfX amount of token X to be sold
     * @return amountOfY amount of token Y to be received
     */
    function _calculateAmountOfYReceivedSellingX(
        packedFloat _amountOfX
    ) internal view virtual returns (packedFloat amountOfY);

    /**
     * This function calculates the amount of token X the user will receive when selling token Y (sell y for x : in perspective).
     * @param _amountOfY amount of token Y to be sold
     * @return amountOfX amount of token X to be received
     */
    function _calculateAmountOfXReceivedSellingY(
        packedFloat _amountOfY
    ) internal view virtual returns (packedFloat amountOfX);

    /**
     * @dev This function cleans the state of the calculator in the case of the pool closing.
     */
    function _clearState() internal virtual;

    /**
     * @dev This function validates the liquidity addition to ensure it does not exceed the max supply of xToken.
     * @param afterBalance the balance of xToken after the addition
     */
    function _validateLiquidityAdd(packedFloat afterBalance) internal view virtual;
}
