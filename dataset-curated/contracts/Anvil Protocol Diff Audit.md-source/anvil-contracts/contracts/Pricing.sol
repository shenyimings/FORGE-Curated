// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

/**
 * @title Library with often used math-related helper functions related to the Anvil protocol.
 *
 * @custom:security-contact security@af.xyz
 */
library Pricing {
    error CastOverflow(uint256 input);

    /// Example: human-readable price is 25000, {price: 25, exponent: 3, ...}
    /// Example: human-readable price is 0.00004, {price: 4, exponent: -5, ...}
    struct OraclePrice {
        // Price
        uint256 price;
        // The exchange rate may be a decimal, but it will always be represented as a uint256.
        // The price should be multiplied by 10**exponent to get the proper scale.
        int32 exponent;
        // Unix timestamp describing when the price was published
        uint256 publishTime;
    }

    /**
     * @notice Calculates the collateral factor implied by the provided amounts of collateral and credited tokens.
     * @param _collateralTokenAmount The amount of the collateral token.
     * @param _creditedTokenAmount The amount of the credited token.
     * @param _price The price of the market in which the collateral is the input token and credited is the output token.
     * @return The calculated collateral factor in basis points.
     */
    function collateralFactorInBasisPoints(
        uint256 _collateralTokenAmount,
        uint256 _creditedTokenAmount,
        OraclePrice memory _price
    ) internal pure returns (uint16) {
        uint256 collateralInCredited = collateralAmountInCreditedToken(_collateralTokenAmount, _price);
        // Don't divide by 0
        if (collateralInCredited == 0) {
            return type(uint16).max;
        }

        uint256 collateralFactor = (_creditedTokenAmount * 10_000) / collateralInCredited;
        return collateralFactor > type(uint16).max ? type(uint16).max : uint16(collateralFactor);
    }

    /**
     * @notice Calculates the amount of the credited token the provided collateral would yield, given the provided price.
     * @param _collateralTokenAmount The amount of the collateral token.
     * @param _price The price of the market in which the collateral is the input token and credited is the output token.
     * @return _creditedTokenAmount The calculated amount of the credited token.
     */
    function collateralAmountInCreditedToken(
        uint256 _collateralTokenAmount,
        OraclePrice memory _price
    ) internal pure returns (uint256) {
        if (_price.exponent < 0) {
            return (_collateralTokenAmount * _price.price) / (10 ** uint256(int256(-1 * _price.exponent)));
        } else {
            return _collateralTokenAmount * _price.price * (10 ** uint256(int256(_price.exponent)));
        }
    }

    /**
     * @notice Calculates the provided percentage of the provided amount.
     * @param _amount The base amount for which the percentage will be calculated.
     * @param _percentageBasisPoints The percentage, represented in basis points. For example, 10_000 is 100%.
     * @return The resulting percentage.
     */
    function percentageOf(uint256 _amount, uint256 _percentageBasisPoints) internal pure returns (uint256) {
        return (_amount * _percentageBasisPoints) / 10_000;
    }

    /**
     * @notice Gets the result of the provided amount being increased by a relative fee.
     * @dev This is the exact reverse of the `amountBeforeFee` function. Please note that calling one
     * and then the other is not guaranteed to produce the starting value due to integer math.
     * @param _amount The amount, to which the fee will be added.
     * @param _feeBasisPoints The relative basis points value that amount should be increased by.
     * @return The resulting amount with the relative fee applied.
     */
    function amountWithFee(uint256 _amount, uint16 _feeBasisPoints) internal pure returns (uint256) {
        return _amount + percentageOf(_amount, uint256(_feeBasisPoints));
    }

    /**
     * @notice Given an amount with a relative fee baked in, returns the amount before the fee was added.
     * @dev This is the exact reverse of the `amountWithFee` function. Please note that calling one
     * and then the other is not guaranteed to produce the starting value due to integer math.
     * @param _amountWithFee The amount that includes the provided fee in its value.
     * @param _feeBasisPoints The basis points value of the fee baked into the provided amount.
     * @return The value of _amountWithFee before the _feeBasisPoints was added to it.
     */
    function amountBeforeFee(uint256 _amountWithFee, uint16 _feeBasisPoints) internal pure returns (uint256) {
        return (_amountWithFee * 10_000) / (10_000 + _feeBasisPoints);
    }

    /**
     * @dev Calculates the amount that is proportional to the provided fraction, given the denominator of the amount.
     * For instance if a1/a2 = b1/b2, then b1 = calculateProportionOfTotal(a1, a2, b2).
     * @param _aPortion The numerator of the reference proportion used to calculate the other numerator.
     * @param _aTotal The numerator of the reference proportion used to calculate the other numerator.
     * @param _bTotal The denominator for which we are calculating the numerator such that aPortion/aTotal = bPortion/bTotal.
     * @param _bPortion The numerator that is an equal proportion of _bTotal that _aPortion is to _aTotal.
     */
    function calculateProportionOfTotal(
        uint256 _aPortion,
        uint256 _aTotal,
        uint256 _bTotal
    ) internal pure returns (uint256 _bPortion) {
        if (_aTotal == 0) return 0;

        // NB: It is a conscious choice to not catch overflows before they happen. This means that callers need to
        // handle possible overflow reverts, but it saves gas for the great majority of cases.

        // _bPortion / _bTotal = _aPortion / _aTotal;
        // _bPortion = _bTotal * _aPortion / _aTotal
        _bPortion = (_bTotal * _aPortion) / _aTotal;
    }

    /**
     * @dev Safely casts the provided uint256 to an int256, reverting with CastOverflow on overflow.
     * @param _input The input uint256 to cast.
     * @return The safely casted uint256.
     */
    function safeCastToInt256(uint256 _input) internal pure returns (int256) {
        if (_input > uint256(type(int256).max)) {
            revert CastOverflow(_input);
        }
        return int256(_input);
    }
}
