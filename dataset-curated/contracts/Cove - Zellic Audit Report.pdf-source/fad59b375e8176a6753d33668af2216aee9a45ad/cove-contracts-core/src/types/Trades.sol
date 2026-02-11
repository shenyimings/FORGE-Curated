// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @notice Struct containing data for an internal trade.
struct InternalTrade {
    // Address of the basket that is selling.
    address fromBasket;
    // Address of the token to sell.
    address sellToken;
    // Address of the token to buy.
    address buyToken;
    // Address of the basket that is buying.
    address toBasket;
    // Amount of the token to sell.
    uint256 sellAmount;
    // Minimum amount of the buy token that the trade results in. Used to check that the proposers oracle prices
    // are correct.
    uint256 minAmount;
    // Maximum amount of the buy token that the trade can result in.
    uint256 maxAmount;
}

/// @notice Struct containing data for an external trade.
struct ExternalTrade {
    // Address of the token to sell.
    address sellToken;
    // Address of the token to buy.
    address buyToken;
    // Amount of the token to sell.
    uint256 sellAmount;
    // Minimum amount of the buy token that the trade results in.
    uint256 minAmount;
    // Array of basket trade ownerships.
    BasketTradeOwnership[] basketTradeOwnership;
}

/// @notice Struct representing a baskets ownership of an external trade.
struct BasketTradeOwnership {
    // Address of the basket.
    address basket;
    // Ownership of the trade with a base of 1e18. An ownershipe of 1e18 means the basket owns the entire trade.
    uint96 tradeOwnership;
}
