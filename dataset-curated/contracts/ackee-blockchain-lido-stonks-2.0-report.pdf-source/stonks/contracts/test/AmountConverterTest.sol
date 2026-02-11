// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AmountConverter} from "../AmountConverter.sol";

contract AmountConverterTest {
    // ==================== Constants ====================

    /// @notice Maximum basis points (200%).
    uint256 public constant MAX_BASIS_POINTS = 20_000;
    /// @notice Minimum basis points (0%).
    uint256 public constant MIN_BASIS_POINTS = 0;

    // ==================== Storage Variables ====================

    /// @notice AmountConverter instance used for testing.
    AmountConverter public amountConverter;
    /// @notice Multiplier in basis points applied to converter output for testing.
    uint256 public multiplierInBP = 1e4;

    // ==================== Constructor ====================

    /**
     * @notice Initializes the test contract with an AmountConverter instance.
     * @param oracleRouter_ Oracle router address.
     * @param allowedTokensToSell_ Array of allowed sell tokens.
     * @param allowedTokensToBuy_ Array of allowed buy tokens.
     * @param useEthAnchor_ If true, uses ETH-anchored pricing.
     */
    constructor(
        address oracleRouter_,
        address[] memory allowedTokensToSell_,
        address[] memory allowedTokensToBuy_,
        bool useEthAnchor_
    ) {
        amountConverter = new AmountConverter(
            oracleRouter_,
            allowedTokensToSell_,
            allowedTokensToBuy_,
            useEthAnchor_
        );
    }

    // ==================== Public Functions ====================

    /**
     * @notice Sets the multiplier for answer adjustments.
     * @param multiplierInBP_ Multiplier in basis points.
     */
    function multiplyAnswer(uint256 multiplierInBP_) public {
        if (multiplierInBP_ > MAX_BASIS_POINTS) {
            revert("Error");
        }

        if (multiplierInBP_ <= 0) {
            revert("Error");
        }

        multiplierInBP = multiplierInBP_;
    }

    // ==================== External View Functions ====================

    /**
     * @notice Gets expected output with multiplier applied.
     * @param tokenFrom Token to sell.
     * @param tokenTo Token to buy.
     * @param amount Amount to sell.
     * @return Expected output amount.
     */
    function getExpectedOut(
        address tokenFrom,
        address tokenTo,
        uint256 amount
    ) external view returns (uint256) {
        return (amountConverter.getExpectedOut(tokenFrom, tokenTo, amount) * multiplierInBP) / 1e4;
    }
}
