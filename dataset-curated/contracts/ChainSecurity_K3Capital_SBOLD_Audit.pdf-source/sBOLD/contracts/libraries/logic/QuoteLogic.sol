// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISBold} from "../../interfaces/ISBold.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../helpers/Constants.sol";

/// @title QuoteLogic
/// @notice Logic for quotes derivation.
library QuoteLogic {
    using Math for uint256;

    /// @param oracle The oracle to use for getting the quote.
    /// @param balances The collateral balance structs.
    /// @param _revert If the getQuote should revert or not.
    /// @return success The success result of this function.
    /// @return amount The aggregated amount of collateral in USD.
    function getAggregatedQuote(
        IPriceOracle oracle,
        ISBold.CollBalance[] memory balances,
        bool _revert
    ) internal view returns (bool success, uint256 amount) {
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i].balance == 0) continue;

            try oracle.getQuote(balances[i].balance, balances[i].addr) returns (uint256 amount_) {
                amount += amount_;
            } catch (bytes memory data) {
                if (_revert) revert(string(data));

                return (false, amount);
            }
        }

        return (true, amount);
    }

    /// @param oracle The oracle to use for getting the quote.
    /// @param bold The address of $BOLD.
    /// @param coll The address of the collateral.
    /// @param balance The balance to return quote for.
    /// @return amount The quote amount of collateral in $BOLD.
    function getInBoldQuote(
        IPriceOracle oracle,
        address bold,
        address coll,
        uint256 balance,
        uint8 decimals
    ) internal view returns (uint256) {
        // Get collateral value in USD
        uint256 collQuote = oracle.getQuote(balance, coll);
        // Get $BOLD value in USD
        uint256 boldUnitQuote = oracle.getQuote(10 ** decimals, bold);
        // Calculate 1 $BOLD * `n` collateral
        return collQuote.mulDiv(10 ** Constants.ORACLE_PRICE_PRECISION, boldUnitQuote);
    }
}
