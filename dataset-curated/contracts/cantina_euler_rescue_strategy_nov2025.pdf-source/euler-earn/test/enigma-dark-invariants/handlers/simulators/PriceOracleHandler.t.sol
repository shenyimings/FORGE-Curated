// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title PriceOracleHandler
/// @notice Handler test contract for the  PriceOracle actions
contract PriceOracleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARIABLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice This function simulates price changes in unitOfAccount of the base assets
    function setPrice(uint256 price, uint8 i) external {
        require(price > 0, "PriceOracleHandler: price must be greater than 0");
        require(price < 1000000 * 1e18, "PriceOracleHandler: price must be les than 1M");

        address baseAsset = _getRandomBaseAsset(i);

        oracle.setPrice(baseAsset, unitOfAccount, price);
    }

    /// @notice This function simulates smaller changes in the price of an asset
    function changePrice(uint16 deltaPercentage, bool up, uint8 i) external {
        address baseAsset = _getRandomBaseAsset(i);

        deltaPercentage = uint16(clampLe(deltaPercentage, 1e4));

        uint256 price = oracle.getQuote(1e18, baseAsset, unitOfAccount);

        if (up) {
            price = price + (price * deltaPercentage) / 1e4;
        } else {
            price = price - (price * deltaPercentage) / 1e4;
        }

        oracle.setPrice(baseAsset, unitOfAccount, price);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
