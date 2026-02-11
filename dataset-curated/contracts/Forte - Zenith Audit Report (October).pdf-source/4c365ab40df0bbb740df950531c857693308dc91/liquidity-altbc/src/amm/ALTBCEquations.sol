// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {MathLibs, packedFloat} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import {NegativeValue} from "liquidity-base/src/common/IErrors.sol";

/**
 * @title Equations used by the ALTBC AMM
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
library ALTBCEquations {
    using MathLibs for int256;
    using MathLibs for packedFloat;

    packedFloat constant FLOAT_2 = packedFloat.wrap(0x7f6c00000000000000000000000000000f0bdc21abb48db201e86d4000000000); // encoded previously to save gas
    packedFloat constant FLOAT_NEG_1 = packedFloat.wrap(0x7f6d00000000000000000000000000000785ee10d5da46d900f436a000000000); // encoded previously to save gas
    packedFloat constant FLOAT_0 = packedFloat.wrap(0); // encoded previously to save gas
    packedFloat constant FLOAT_1 = packedFloat.wrap(0x7f6c00000000000000000000000000000785ee10d5da46d900f436a000000000); // encoded previously to save gas
    packedFloat constant FLOAT_WAD = packedFloat.wrap(57507338264406853159277167054180511853162945875507645848942038639672188469248);

    /**
     * @dev This function calculates B(n) and stores it in the tbc definition as b.
     * @notice The result will be a packedFloat
     * @notice Bn is equal to V / (Xn + C) in the spec
     * @param altbc the tbc definition
     * @param Xn the X value at n
     */
    function calculateBn(ALTBCDef storage altbc, packedFloat Xn) internal {
        altbc.b = altbc.V.div(Xn.add(altbc.C));
    }

    /**
     * @dev This function calculates f(x) at n.
     * @notice The result for f(x) will be a packedFloat.
     * @notice This equation is used to calculate the spot price of the x token and is equal to (bn * x) + cn
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
     * @notice This equation is used to calculate the area under the curve at n and is equal to (1/2)(bn*x^2) + cn*x
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
     * @notice This equation in the spec is equal to (Ln + Zn) / (Wn - wInactive) + phi
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
     * @notice This equation in the spec is equal to 2Dn / (c + sqrt(c^2 + 2bDn))
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
    function calculateC(ALTBCDef storage altbc, packedFloat Xn, packedFloat oldBn) internal {
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

    /**
     * @dev This function calculates the parameter L.
     * @param altbc the tbc definition.
     * @param Xn the x coordinate
     * @return result the calculate L parameter.
     */
    function calculateL(ALTBCDef storage altbc, packedFloat Xn) internal view returns (packedFloat result) {
        packedFloat firstTerm = (altbc.xMin.add(altbc.C)).divL(Xn.add(altbc.C));
        packedFloat ln = firstTerm.ln();
        packedFloat secondTerm = ((altbc.b.mul(Xn)).add((altbc.c.mul(FLOAT_2)))).add(altbc.V.mul(ln));
        result = secondTerm.mul(altbc.xMin.div(FLOAT_2));
    }

    /**
     * @dev This function calculates the parameter Z, which is a balancing quantity used to ensure fair LP accounting.
     * @param altbc the tbc definition.
     * @param Ln the liquidity parameter.
     * @param Wn the total amount of units of liquidity in circulation.
     * @param WIn the total amount of units of liquidity in circulation.
     * @param q the liquidity units to receive in exchange for A and B
     * @param withdrawal the boolean value for withdrawal
     */
    function calculateZ(ALTBCDef storage altbc, packedFloat Ln, packedFloat Wn, packedFloat WIn, packedFloat q, bool withdrawal) internal {
        if (withdrawal) {
            q = q.mul(FLOAT_NEG_1);
        }
        packedFloat activeLiquidity = Wn.sub(WIn);
        altbc.Zn = activeLiquidity.eq(FLOAT_0)
            ? FLOAT_0
            : altbc.Zn.add(((WIn.div((activeLiquidity))).mul(q)).mul((Ln.add(altbc.Zn)))).add((q.mul(altbc.Zn)));
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
        if (deltaD.lt(FLOAT_0)) deltaD = FLOAT_0;
        packedFloat bParam = _B.mul(deltaX);
        packedFloat aParam = _A.mul(deltaD);
        if ((bParam).le(aParam)) {
            B = _B;
            if (deltaD.lt(FLOAT_WAD)) {
                A = _A;
                q = A.div(deltaX);
            } else {
                A = deltaX.div(deltaD).mul(_B);
                q = B.div(deltaD);
            }
        } else {
            A = _A;
            B = deltaD.div(deltaX).mul(_A);
            q = A.div(deltaX);
        }
    }

    /**
     * @dev This function calculates the revenue available for a given LPToken.
     * @param wj The share of the pool's liquidity the associated LPToken represents.
     * @param hn The revenue parameter.
     * @param rj The last revenue claim for the associated LPToken.
     * @return result The calculated revenue available for the LPToken.
     */
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
    function _liquidityUpdateHelper(ALTBCDef storage altbc, packedFloat Xn, packedFloat multiplier) internal returns (packedFloat x) {
        x = Xn.mul(multiplier);

        altbc.b = altbc.b.div(multiplier);
        altbc.xMax = altbc.xMax.mul(multiplier);
        altbc.xMin = altbc.xMin.mul(multiplier);
        altbc.C = altbc.C.mul(multiplier);
    }
}
