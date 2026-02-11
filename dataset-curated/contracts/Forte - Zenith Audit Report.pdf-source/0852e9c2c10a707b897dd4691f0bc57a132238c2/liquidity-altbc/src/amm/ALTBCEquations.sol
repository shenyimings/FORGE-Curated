// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MathLibs, packedFloat, Float} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import {NegativeValue} from "liquidity-base/src/common/IErrors.sol";
import {BaseEquations} from "liquidity-base/src/amm/base/BaseEquations.sol";

/**
 * @title Equations used by the ALTBC AMM
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
library ALTBCEquations {
    using MathLibs for uint256;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using MathLibs for Float;
    uint constant MOST_SIGNIFICANT_BIT_SET_TO_1 = 0x8000000000000000000000000000000000000000000000000000000000000000;
    packedFloat constant FLOAT_2 = packedFloat.wrap(11125211704113162124471569415374229905342464); // encoded previously to save gas
    packedFloat constant FLOAT_NEG_1 = packedFloat.wrap(11125541986480083062935032789981661673553920); // encoded previously to save gas
    packedFloat constant FLOAT_0 = packedFloat.wrap(0); // encoded previously to save gas
    packedFloat constant FLOAT_1 = packedFloat.wrap(11125201704113162124471569415374229905342464); // encoded previously to save gas
    /**
     * @dev This function calculates B(n) and stores it in the tbc definition as b.
     * @notice The result will be a packedFloat
     * @param altbc the tbc definition
     * @param Xn the X value at n
     */
    function calculateBn(ALTBCDef storage altbc, packedFloat Xn) internal {
        altbc.b = altbc.V.div(Xn.add(altbc.C));
    }

    /**
     * @dev This function calculates f(x) at n.
     * @notice The result for f(x) will be a packedFloat.
     * @param altbc the tbc definition
     * @param x value for x at n
     * @return result the calculated f(x), this value will be a packedFloat
     */
    function calculatefx(ALTBCDef storage altbc, packedFloat x) internal view returns (packedFloat result) {
        result = altbc.b.mul(x).add(altbc.c);
    }

    /**
     * @dev This function calculates D at n.
     * @notice The result for Dn will be a packedFloat
     * @param altbc the tbc definition
     * @param x value for x at n
     * @return result
     */
    function calculateDn(ALTBCDef storage altbc, packedFloat x) internal view returns (packedFloat result) {
        result = ((altbc.b.mul((x).mul(x))).div(FLOAT_2)).add(altbc.c.mul(x));
    }

    /**
     * @dev This function calculates h at n which is the total revenue per unit of liquidity at time n.
     * @notice This method is implemented using packedFloats and the float128 library
     * @param L the x coordinate
     * @param W the total amount of units of liquidity in circulation
     * @param phi the total amount of units of liquidity in circulation
     * @return result the calculated h
     */
    function calculateH(
        ALTBCDef storage altbc,
        packedFloat L,
        packedFloat W,
        packedFloat wInactive,
        packedFloat phi
    ) internal view returns (packedFloat result) {
        result = ((L.add(altbc.Zn)).div((W.sub(wInactive)))).add(phi);
    }

    /**
     * @dev This function calculates the value of Xn+1.
     * @notice This method is implemented using packedFloats and the float128 library
     * @param altbc the tbc definition
     * @param Dn the area under the curve.
     * @return newX the calculated Xn+1
     */
    function calculateXofNPlus1(ALTBCDef storage altbc, packedFloat Dn) internal view returns (packedFloat newX) {
        newX = FLOAT_2.mul(Dn).div(altbc.c.add((altbc.c.mul(altbc.c).add(FLOAT_2.mul(altbc.b).mul(Dn))).sqrt()));
    }

    /**
     * @dev This function calculates the parameter c and stores it in the tbc definition.
     * @param altbc the tbc definition.
     * @param Xn the x coordinate
     * @param oldBn the previous state of b
     */
    function calculateCNew(ALTBCDef storage altbc, packedFloat Xn, packedFloat oldBn) internal {
        packedFloat firstTerm;
        if (altbc.b.gt(oldBn)) {
            firstTerm = (altbc.b.sub(oldBn)).div(FLOAT_2);
            firstTerm = firstTerm.mul(Xn);
            if (firstTerm.gt(altbc.c)) revert NegativeValue();
            else altbc.c = altbc.c.sub(firstTerm);
        } else {
            firstTerm = (oldBn.sub(altbc.b)).div(FLOAT_2);
            firstTerm = firstTerm.mul(Xn);
            altbc.c = altbc.c.add(firstTerm);
        }
    }

    /**
     * @dev This function calculates the last revenue claim to be stored in the associated LPToken variable r.
     * @notice The result for last revenue claim.
     * @param hn The revenue parameter.
     * @param wj The share of the pool's liquidity the associated LPToken represents.
     * @param r_hat The current last revenue claim value of the associated LPToken.
     * @param w_hat The current liquidity amount of the associated LPToken.
     */
    function calculateLastRevenueClaim(
        packedFloat hn,
        packedFloat wj,
        packedFloat r_hat,
        packedFloat w_hat
    ) internal pure returns (packedFloat result) {
        result = BaseEquations.calculateLastRevenueClaim(hn, wj, r_hat, w_hat);
    }

    /**
     * @dev This function calculates the parameter L.
     * @param altbc the tbc definition.
     * @param Xn the x coordinate
     * @return result the calculate L parameter.
     */
    function calculateL(ALTBCDef storage altbc, packedFloat Xn) internal view returns (packedFloat result) {
        packedFloat firstTerm = (altbc.xMin.add(altbc.C)).div(Xn.add(altbc.C));
        // Replace this when the float128 ln is available. (Will increase precision)
        uint256 lnDoubleWAD = uint(firstTerm.convertpackedFloatToDoubleWAD()).lnWAD2Negative();
        packedFloat ln = int(lnDoubleWAD).toPackedFloat(-36).mul(FLOAT_NEG_1);
        packedFloat secondTerm = ((altbc.b.mul(Xn)).add((altbc.c.mul(FLOAT_2)))).add(altbc.V.mul(ln));
        result = secondTerm.mul(altbc.xMin.div(FLOAT_2));
    }

    function calculateZ(ALTBCDef storage altbc, packedFloat Ln, packedFloat Wn, packedFloat WIn, packedFloat q, bool withdrawal) internal {
        if (withdrawal) {
            q = q.mul(FLOAT_NEG_1);
        }

        altbc.Zn = altbc.Zn.add(((WIn.div((Wn.sub(WIn)))).mul(q)).mul((Ln.add(altbc.Zn)))).add((q.mul(altbc.Zn)));
    }

    /**
     * @dev This function calculates q.
     * @param altbc the tbc definition.
     * @param Xn the x coordinate
     * @param _A The amount of incoming X Token.
     * @param _B The amount of incoming collateral.
     * @param L the liquidity parameter.
     * @param Dn The current area under the curve.
     * @return A the actual amount to take for token x
     * @return B the actual amount to take for token y
     * @return q the liquidity units to receive in exchange for A and B
     */
    function calculateQ(
        ALTBCDef storage altbc,
        packedFloat Xn,
        packedFloat _A,
        packedFloat _B,
        packedFloat L,
        packedFloat Dn
    ) internal view returns (packedFloat A, packedFloat B, packedFloat q) {
        packedFloat deltaX = altbc.xMax.sub(Xn);
        packedFloat deltaD = Dn.sub(L);
        packedFloat bParam = _B.mul(deltaX);
        packedFloat aParam = _A.mul(deltaD);
        if ((bParam).le(aParam)) {
            B = _B;
            if (deltaD.eq(FLOAT_0)) {
                A = _A;
                q = A.div(deltaX);
            } else {
                A = bParam.div(deltaD);
                q = B.div(deltaD);
            }
        } else {
            A = _A;
            B = aParam.div(deltaX);
            q = A.div(deltaX);
        }
    }

    function calculateRevenueAvailable(packedFloat wj, packedFloat hn, packedFloat rj) internal pure returns (packedFloat result) {
        return wj.mul(hn.sub(rj));
    }

    /**
     * @dev This function updates related tbc variables when a liquidity deposit or withdrawal is made
     * @param altbc the tbc definition.
     * @param Xn the x coordinate.
     * @param multiplier The value for multiplier for pool state
     * @return x The updated x value.
     */
    function _liquidityUpdateHelper(
        ALTBCDef storage altbc,
        packedFloat Xn,
        packedFloat multiplier
    ) internal returns (packedFloat x) {
        x = Xn.mul(multiplier);

        altbc.b = altbc.b.div(multiplier);
        altbc.xMax = altbc.xMax.mul(multiplier);
        altbc.xMin = altbc.xMin.mul(multiplier);
        altbc.C = altbc.C.mul(multiplier);
    }
}
