// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Libraries
import {ABDKMathQuad} from "./ABDKMathQuad.sol";

/// @title Black-Scholes option pricing formula and supporting statistical functions
/// @author Dopex
/// @notice This library implements the Black-Scholes model to price options.
/// See - https://en.wikipedia.org/wiki/Black%E2%80%93Scholes_model
/// @dev Implements the following implementation - https://cseweb.ucsd.edu/~goguen/courses/130/SayBlackScholes.html
/// Uses the ABDKMathQuad(https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMathQuad.md)
/// library to make precise calculations. It uses a DIVISOR (1e16) for maintaining precision in constants.
library BlackScholes {
    uint8 internal constant OPTION_TYPE_CALL = 0;
    uint8 internal constant OPTION_TYPE_PUT = 1;

    uint256 internal constant DIVISOR = 10 ** 16;

    /**
     * @notice The function that uses the Black-Scholes equation to calculate the option price
     * See http://en.wikipedia.org/wiki/Black%E2%80%93Scholes_model#Black-Scholes_formula
     * NOTE: The different parts of the equation are broken down to separate functions as using
     * ABDKMathQuad makes small equations verbose.
     * @param optionType Type of option - 0 = call, 1 = put
     * @param price Stock price
     * @param strike Strike price
     * @param timeToExpiry Time to expiry in days
     * @param riskFreeRate Risk-free rate
     * @param volatility Volatility on the asset
     * @return Option price based on the Black-Scholes model
     */
    function calculate(
        uint8 optionType,
        uint256 price,
        uint256 strike,
        uint256 timeToExpiry,
        uint256 riskFreeRate,
        uint256 volatility
    ) internal pure returns (uint256) {
        bytes16 S = ABDKMathQuad.fromUInt(price);
        bytes16 X = ABDKMathQuad.fromUInt(strike);
        bytes16 T = ABDKMathQuad.div(
            ABDKMathQuad.fromUInt(timeToExpiry),
            ABDKMathQuad.fromUInt(36500) // 365 * 10 ^ DAYS_PRECISION
        );
        bytes16 r = ABDKMathQuad.div(ABDKMathQuad.fromUInt(riskFreeRate), ABDKMathQuad.fromUInt(10000));
        bytes16 v = ABDKMathQuad.div(ABDKMathQuad.fromUInt(volatility), ABDKMathQuad.fromUInt(100));
        bytes16 d1 = ABDKMathQuad.div(
            ABDKMathQuad.add(
                ABDKMathQuad.ln(ABDKMathQuad.div(S, X)),
                ABDKMathQuad.mul(
                    ABDKMathQuad.add(r, ABDKMathQuad.mul(v, ABDKMathQuad.div(v, ABDKMathQuad.fromUInt(2)))), T
                )
            ),
            ABDKMathQuad.mul(v, ABDKMathQuad.sqrt(T))
        );
        bytes16 d2 = ABDKMathQuad.sub(d1, ABDKMathQuad.mul(v, ABDKMathQuad.sqrt(T)));
        if (optionType == OPTION_TYPE_CALL) {
            return ABDKMathQuad.toUInt(
                ABDKMathQuad.mul(_calculateCallTimeDecay(S, d1, X, r, T, d2), ABDKMathQuad.fromUInt(DIVISOR))
            );
        } else if (optionType == OPTION_TYPE_PUT) {
            return ABDKMathQuad.toUInt(
                ABDKMathQuad.mul(_calculatePutTimeDecay(X, r, T, d2, S, d1), ABDKMathQuad.fromUInt(DIVISOR))
            );
        } else {
            return 0;
        }
    }

    /// @dev Function to caluclate the call time decay
    /// From the implementation page(https://cseweb.ucsd.edu/~goguen/courses/130/SayBlackScholes.html); part of the equation
    /// ( S * CND(d1)-X * Math.exp(-r * T) * CND(d2) );
    function _calculateCallTimeDecay(bytes16 S, bytes16 d1, bytes16 X, bytes16 r, bytes16 T, bytes16 d2)
        internal
        pure
        returns (bytes16)
    {
        return ABDKMathQuad.sub(
            ABDKMathQuad.mul(S, CND(d1)),
            ABDKMathQuad.mul(ABDKMathQuad.mul(X, ABDKMathQuad.exp(ABDKMathQuad.mul(ABDKMathQuad.neg(r), T))), CND(d2))
        );
    }

    /// @dev Function to caluclate the put time decay
    /// From the implementation page(https://cseweb.ucsd.edu/~goguen/courses/130/SayBlackScholes.html); part of the equation -
    /// ( X * Math.exp(-r * T) * CND(-d2) - S * CND(-d1) );
    function _calculatePutTimeDecay(bytes16 X, bytes16 r, bytes16 T, bytes16 d2, bytes16 S, bytes16 d1)
        internal
        pure
        returns (bytes16)
    {
        bytes16 price_part1 = ABDKMathQuad.mul(
            ABDKMathQuad.mul(X, ABDKMathQuad.exp(ABDKMathQuad.mul(ABDKMathQuad.neg(r), T))), CND(ABDKMathQuad.neg(d2))
        );
        bytes16 price_part2 = ABDKMathQuad.mul(S, CND(ABDKMathQuad.neg(d1)));
        bytes16 price = ABDKMathQuad.sub(price_part1, price_part2);
        return price;
    }

    /**
     * @notice Normal cumulative distribution function.
     * See http://en.wikipedia.org/wiki/Normal_distribution#Cumulative_distribution_function
     * From the implementation page(https://cseweb.ucsd.edu/~goguen/courses/130/SayBlackScholes.html); part of the equation -
     * "k = 1 / (1 + .2316419 * x); return ( 1 - Math.exp(-x * x / 2)/ Math.sqrt(2*Math.PI) * k * (.31938153 + k * (-.356563782 + k * (1.781477937 + k * (-1.821255978 + k * 1.330274429)))) );"
     * NOTE: The different parts of the equation are broken down to separate functions as using
     * ABDKMathQuad makes small equations verbose.
     */
    function CND(bytes16 x) internal pure returns (bytes16) {
        if (ABDKMathQuad.toInt(x) < 0) {
            return (ABDKMathQuad.sub(ABDKMathQuad.fromUInt(1), CND(ABDKMathQuad.neg(x))));
        } else {
            bytes16 k = ABDKMathQuad.div(
                ABDKMathQuad.fromUInt(1),
                ABDKMathQuad.add(
                    ABDKMathQuad.fromUInt(1),
                    ABDKMathQuad.mul(
                        ABDKMathQuad.div(ABDKMathQuad.fromUInt(2316419000000000), ABDKMathQuad.fromUInt(DIVISOR)), x
                    )
                )
            );
            bytes16 CND_part2 = _getCNDPart2(k, x);
            return ABDKMathQuad.sub(ABDKMathQuad.fromUInt(1), CND_part2);
        }
    }

    function _getCNDPart2(bytes16 k, bytes16 x) internal pure returns (bytes16) {
        return ABDKMathQuad.mul(_getCNDPart2_1(x), _getCNDPart2_2(k));
    }

    function _getCNDPart2_1(bytes16 x) internal pure returns (bytes16) {
        return ABDKMathQuad.div(
            ABDKMathQuad.exp(ABDKMathQuad.mul(ABDKMathQuad.neg(x), ABDKMathQuad.div(x, ABDKMathQuad.fromUInt(2)))),
            ABDKMathQuad.sqrt(
                ABDKMathQuad.mul(
                    ABDKMathQuad.fromUInt(2),
                    ABDKMathQuad.div(ABDKMathQuad.fromUInt(31415926530000000), ABDKMathQuad.fromUInt(DIVISOR))
                )
            )
        );
    }

    function _getCNDPart2_2(bytes16 k) internal pure returns (bytes16) {
        return ABDKMathQuad.mul(
            ABDKMathQuad.add(
                ABDKMathQuad.div(ABDKMathQuad.fromUInt(3193815300000000), ABDKMathQuad.fromUInt(DIVISOR)),
                ABDKMathQuad.mul(
                    k,
                    ABDKMathQuad.add(
                        ABDKMathQuad.neg(
                            ABDKMathQuad.div(ABDKMathQuad.fromUInt(3565637820000000), ABDKMathQuad.fromUInt(DIVISOR))
                        ),
                        ABDKMathQuad.mul(
                            k,
                            ABDKMathQuad.add(
                                ABDKMathQuad.div(
                                    ABDKMathQuad.fromUInt(17814779370000000), ABDKMathQuad.fromUInt(DIVISOR)
                                ),
                                _getCNDPart2_2_1(k)
                            )
                        )
                    )
                )
            ),
            k
        );
    }

    function _getCNDPart2_2_1(bytes16 k) internal pure returns (bytes16) {
        return ABDKMathQuad.mul(
            k,
            ABDKMathQuad.add(
                ABDKMathQuad.neg(
                    ABDKMathQuad.div(ABDKMathQuad.fromUInt(18212559780000000), ABDKMathQuad.fromUInt(DIVISOR))
                ),
                ABDKMathQuad.mul(
                    k, ABDKMathQuad.div(ABDKMathQuad.fromUInt(13302744290000000), ABDKMathQuad.fromUInt(DIVISOR))
                )
            )
        );
    }
}
