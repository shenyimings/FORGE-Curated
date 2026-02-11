// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {DEFAULT_PRECISION} from "../utils/Constants.sol";
import {InvalidPrice} from "../interfaces/Errors.sol";
import {TRADING_MODULE} from "../interfaces/ITradingModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AbstractCustomOracle} from "./AbstractCustomOracle.sol";

/// @notice Returns the value of one LP token in terms of the primary index token. Will revert if the spot
/// price on the pool is not within some deviation tolerance of the implied oracle price. This is intended
/// to prevent any pool manipulation. The value of the LP token is calculated as the value of the token if
/// all the balance claims are withdrawn proportionally and then converted to the primary currency at the
/// oracle price.
abstract contract AbstractLPOracle is AbstractCustomOracle {

    /// @dev The precision of the pool, generally 1e18
    uint256 internal immutable POOL_PRECISION;
    /// @dev Defines the lower limit of a tolerable price deviation from the oracle price
    uint256 internal immutable LOWER_LIMIT_MULTIPLIER;
    /// @dev Defines the upper limit of a tolerable price deviation from the oracle price
    uint256 internal immutable UPPER_LIMIT_MULTIPLIER;
    /// @dev The address of the LP token
    address internal immutable LP_TOKEN;
    /// @dev The index of the primary index token in the LP token, the price will be returned
    /// in terms of this token
    uint8 internal immutable PRIMARY_INDEX;

    constructor(
        uint256 _poolPrecision,
        uint256 _lowerLimitMultiplier,
        uint256 _upperLimitMultiplier,
        address _lpToken,
        uint8 _primaryIndex,
        string memory description_,
        address sequencerUptimeOracle_
    ) AbstractCustomOracle(
        description_,
        sequencerUptimeOracle_
    ) {
        require(_lowerLimitMultiplier < DEFAULT_PRECISION);
        require(DEFAULT_PRECISION < _upperLimitMultiplier);

        POOL_PRECISION = _poolPrecision;
        // These are in "default precision" terms, so 0.99e18 is 99%
        LOWER_LIMIT_MULTIPLIER = _lowerLimitMultiplier;
        UPPER_LIMIT_MULTIPLIER = _upperLimitMultiplier;
        LP_TOKEN = _lpToken;
        PRIMARY_INDEX = _primaryIndex;
    }

    function _totalPoolSupply() internal view virtual returns (uint256) {
        return ERC20(LP_TOKEN).totalSupply();
    }

    /// @notice Returns the pair price of two tokens via the TRADING_MODULE which holds a registry
    /// of oracles. Will revert of the oracle pair is not listed.
    function _getOraclePairPrice(address base, address quote) internal view returns (uint256) {
        // The trading module always returns a positive rate in DEFAULT_PRECISION so we can safely
        // cast to uint256
        (int256 rate, /* */) = TRADING_MODULE.getOraclePrice(base, quote);
        return uint256(rate);
    }

    /// @notice Calculates the claim of one LP token on relevant pool balances
    /// and compares the oracle price to the spot price, reverting if the deviation is too high.
    /// @return oneLPValueInPrimary the value of one LP token in terms of the primary index token,
    /// scaled to default precision (1e18)
    function _calculateLPTokenValue(
        ERC20[] memory tokens,
        uint8[] memory decimals,
        uint256[] memory balances,
        uint256[] memory spotPrices
    ) internal view returns (uint256) {
        address primaryToken = address(tokens[PRIMARY_INDEX]);
        uint256 primaryDecimals = 10 ** decimals[PRIMARY_INDEX];
        uint256 totalSupply = _totalPoolSupply();
        uint256 oneLPValueInPrimary;

        for (uint256 i; i < tokens.length; i++) {
            // Skip the pool token if it is in the token list (i.e. Balancer V2 ComposablePools)
            if (address(tokens[i]) == address(LP_TOKEN)) continue;
            // This is the claim on the pool balance of 1 LP token in terms of the token's native
            // precision
            uint256 tokenClaim = balances[i] * POOL_PRECISION / totalSupply;
            if (i == PRIMARY_INDEX) {
                oneLPValueInPrimary += tokenClaim;
            } else {
                uint256 price = _getOraclePairPrice(primaryToken, address(tokens[i]));

                // Check that the spot price and the oracle price are near each other. If this is
                // not true then we assume that the LP pool is being manipulated.
                uint256 lowerLimit = price * LOWER_LIMIT_MULTIPLIER / DEFAULT_PRECISION;
                uint256 upperLimit = price * UPPER_LIMIT_MULTIPLIER / DEFAULT_PRECISION;
                if (spotPrices[i] < lowerLimit || upperLimit < spotPrices[i]) {
                    revert InvalidPrice(price, spotPrices[i]);
                }

                // Convert the token claim to primary using the oracle pair price.
                uint256 secondaryDecimals = 10 ** decimals[i];
                // Scale the token claim to primary token precision, DEFAULT_PRECISION is used
                // to match the precision of the oracle pair price.
                oneLPValueInPrimary += (tokenClaim * DEFAULT_PRECISION * primaryDecimals) / 
                    (price * secondaryDecimals);
            }
        }

        // Scale this up to default precision
        return oneLPValueInPrimary * DEFAULT_PRECISION / primaryDecimals;
    }
}