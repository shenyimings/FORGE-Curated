// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.8.20 <0.9.0;

import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

/**
 * @title  Helper library for indexing math functions.
 * @author M0 Labs
 */
library IndexingMath {
    /* ============ Variables ============ */

    /// @notice The scaling of indexes for exponent math.
    uint56 internal constant EXP_SCALED_ONE = 1e12;

    /* ============ Custom Errors ============ */

    /// @notice Emitted when a division by zero occurs.
    error DivisionByZero();

    /* ============ Exposed Functions ============ */

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     * @param  principal The principal amount.
     * @param  index     An index.
     * @return The present amount rounded down.
     */
    function getPresentAmountRoundedDown(uint112 principal, uint128 index) internal pure returns (uint256) {
        unchecked {
            return (uint256(principal) * index) / EXP_SCALED_ONE;
        }
    }

    /**
     * @dev    Returns the present amount (rounded up) given the principal amount and an index.
     * @param  principal The principal amount.
     * @param  index     An index.
     * @return The present amount rounded up.
     */
    function getPresentAmountRoundedUp(uint112 principal, uint128 index) internal pure returns (uint256) {
        unchecked {
            return ((uint256(principal) * index) + (EXP_SCALED_ONE - 1)) / EXP_SCALED_ONE;
        }
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount The present amount.
     * @param  index         An index.
     * @return The principal amount rounded down.
     */
    function getPrincipalAmountRoundedDown(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        if (index == 0) revert DivisionByZero();

        unchecked {
            // NOTE: While `uint256(presentAmount) * EXP_SCALED_ONE` can technically overflow, these divide/multiply functions are
            //       only used for the purpose of principal/present amount calculations for continuous indexing, and
            //       so for an `presentAmount` to be large enough to overflow this, it would have to be a possible result of
            //       `multiply112By128Down` or `multiply112By128Up`, which would already satisfy
            //       `uint256(presentAmount) * EXP_SCALED_ONE < type(uint240).max`.
            return UIntMath.safe112((presentAmount * EXP_SCALED_ONE) / index);
        }
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount The present amount.
     * @param  index         An index.
     * @return The principal amount rounded up.
     */
    function getPrincipalAmountRoundedUp(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        if (index == 0) revert DivisionByZero();

        unchecked {
            // NOTE: While `uint256(presentAmount) * EXP_SCALED_ONE` can technically overflow, these divide/multiply functions are
            //       only used for the purpose of principal/present amount calculations for continuous indexing, and
            //       so for an `presentAmount` to be large enough to overflow this, it would have to be a possible result of
            //       `multiply112By128Down` or `multiply112By128Up`, which would already satisfy
            //       `uint256(presentAmount) * EXP_SCALED_ONE < type(uint240).max`.
            return UIntMath.safe112(((presentAmount * EXP_SCALED_ONE) + index - 1) / index);
        }
    }

    /**
     * @dev    Returns the safely capped principal amount given the present amount, using the current index.
     * @param  presentAmount The present amount.
     * @param  index         An index.
     * @param  maxPrincipalAmount The maximum principal amount.
     * @return The principal amount rounded up, capped at maxPrincipalAmount.
     */
    function getSafePrincipalAmountRoundedUp(
        uint256 presentAmount,
        uint128 index,
        uint112 maxPrincipalAmount
    ) internal pure returns (uint112) {
        uint112 principalAmount = getPrincipalAmountRoundedUp(presentAmount, index);
        return principalAmount > maxPrincipalAmount ? maxPrincipalAmount : principalAmount;
    }
}
