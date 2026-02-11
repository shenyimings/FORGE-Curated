// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import {MathLibs, packedFloat} from "../mathLibs/MathLibs.sol";

/**
 * @title Equations used by multiple TBC types
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
library BaseEquations {
    using MathLibs for uint256;
    using MathLibs for packedFloat;

    /**
     * @dev This function calculates the last revenue claim to be stored in the associated LPToken variable rj. The result will be a WAD value.
     * @notice The result for last revenue claim will be a Float.
     * @param hn The revenue parameter. Expected to be a Float.
     * @param wj The share of the pool's liquidity the associated LPToken represents. Expected to be a Float.
     * @param r_hat The current last revenue claim value of the associated LPToken. Expected to be a Float.
     * @param w_hat The current liquidity amount of the associated LPToken. Expected to be a Float.
     */
    function calculateLastRevenueClaim(
        packedFloat hn,
        packedFloat wj,
        packedFloat r_hat,
        packedFloat w_hat
    ) internal pure returns (packedFloat) {
        return hn.mul(wj).add(r_hat.mul(w_hat)).div(w_hat.add(wj));
    }
}
