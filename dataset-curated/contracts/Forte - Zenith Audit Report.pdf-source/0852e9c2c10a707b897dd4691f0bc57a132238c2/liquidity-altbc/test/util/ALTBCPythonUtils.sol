/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/**
 * @title Utils for interacting with Python
 */
contract ALTBCPythonUtils is Test {
    struct BetaParams {
        uint256 bn;
        uint256 Mn;
        uint256 cn;
        uint256 Xn;
        uint256 A;
        uint256 B;
        uint256 Dv;
        uint256 Dn;
    }

    function _buildFFICalculateBn(uint Xn, uint C, uint256 V) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_bn.py";
        inputs[2] = vm.toString(Xn);
        inputs[3] = vm.toString(C);
        inputs[4] = vm.toString(V);
        return inputs;
    }

    function _buildFFICalculatefx(uint XUpper, uint PUpper, uint PLower, uint Xn, uint cn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_f_x_integrated.py";
        inputs[2] = vm.toString(XUpper);
        inputs[3] = vm.toString(PUpper);
        inputs[4] = vm.toString(PLower);
        inputs[5] = vm.toString(Xn);
        inputs[6] = vm.toString(cn);
        return inputs;
    }

    function _buildFFICalculateFx(uint XUpper, uint PUpper, uint PLower, uint Xn, uint cn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_capital_F_x_integrated.py";
        inputs[2] = vm.toString(XUpper);
        inputs[3] = vm.toString(PUpper);
        inputs[4] = vm.toString(PLower);
        inputs[5] = vm.toString(Xn);
        inputs[6] = vm.toString(cn);
        return inputs;
    }

    function _buildFFICalculateFxInverse(uint cn, uint Bn, uint D) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_F_x_inverse.py";
        inputs[2] = vm.toString(cn);
        inputs[3] = vm.toString(Bn);
        inputs[4] = vm.toString(D);
        return inputs;
    }

    function _buildFFICalculateC(uint Bn, uint OldBn, uint Xn, uint Cn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_c.py";
        inputs[2] = vm.toString(Bn);
        inputs[3] = vm.toString(OldBn);
        inputs[4] = vm.toString(Xn);
        inputs[5] = vm.toString(Cn);
        return inputs;
    }

    function _buildFFICalculateDn(uint Xn, uint Sn, uint Cn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_Dn.py";
        inputs[2] = vm.toString(Xn);
        inputs[3] = vm.toString(Sn);
        inputs[4] = vm.toString(Cn);
        return inputs;
    }

    function _buildFFICalculatePriceEquation(uint Xn, uint Bn, uint Cn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_f_x.py";
        inputs[2] = vm.toString(Xn);
        inputs[3] = vm.toString(Bn);
        inputs[4] = vm.toString(Cn);
        return inputs;
    }

    function _buildFFICalculateCInitial(uint C, uint xMin, uint pLower, uint V) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_c_initial.py";
        inputs[2] = vm.toString(C);
        inputs[3] = vm.toString(xMin);
        inputs[4] = vm.toString(pLower);
        inputs[5] = vm.toString(V);
        return inputs;
    }

    function _buildFFICalculateRMax(uint Xn, uint Bn, uint Cn, uint C, uint xMin, uint Dv, uint R) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](9);
        inputs[0] = "python3";
        inputs[1] = "./script/python/calculate_R_max.py";
        inputs[2] = vm.toString(Xn);
        inputs[3] = vm.toString(Bn);
        inputs[4] = vm.toString(Cn);
        inputs[5] = vm.toString(C);
        inputs[6] = vm.toString(xMin);
        inputs[7] = vm.toString(Dv);
        inputs[8] = vm.toString(R);
        return inputs;
    }

    function _buildFFICalculateDv(uint Xmin, uint V, uint Plower, uint C) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "./script/python/calculate_Dv.py";
        inputs[2] = vm.toString(Xmin);
        inputs[3] = vm.toString(V);
        inputs[4] = vm.toString(Plower);
        inputs[5] = vm.toString(C);
        return inputs;
    }

    function _buildFFICalculateL(
        uint256 _xMin,
        uint256 _V,
        uint256 _b,
        uint256 _c,
        uint _C,
        uint _Xn
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](8);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_L.py";
        inputs[2] = vm.toString(_xMin);
        inputs[3] = vm.toString(_V);
        inputs[4] = vm.toString(_b);
        inputs[5] = vm.toString(_c);
        inputs[6] = vm.toString(_C);
        inputs[7] = vm.toString(_Xn);
        return inputs;
    }

    function _buildFFICalculateXofNPlus1(uint b, uint cn, uint Dn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_x_n_plus_1.py";
        inputs[2] = vm.toString(b);
        inputs[3] = vm.toString(cn);
        inputs[4] = vm.toString(Dn);
        return inputs;
    }

    function _buildFFICalculateZnDeposit(
        uint256 _Ln,
        uint256 _Wn,
        uint256 _WIn,
        uint256 _Zn,
        uint256 _q
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_Zn_Deposit.py";
        inputs[2] = vm.toString(_Ln);
        inputs[3] = vm.toString(_Wn);
        inputs[4] = vm.toString(_WIn);
        inputs[5] = vm.toString(_Zn);
        inputs[6] = vm.toString(_q);
        return inputs;
    }

    function _buildFFICalculateZnWithdrawal(
        uint256 _Ln,
        uint256 _Wn,
        uint256 _WIn,
        uint256 _Zn,
        uint256 _q
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_Zn_Withdrawal.py";
        inputs[2] = vm.toString(_Ln);
        inputs[3] = vm.toString(_Wn);
        inputs[4] = vm.toString(_WIn);
        inputs[5] = vm.toString(_Zn);
        inputs[6] = vm.toString(_q);
        return inputs;
    }

    function _buildFFICalculateZnExtract(
        uint256 _Ln,
        uint256 _Wn,
        uint256 _WIn,
        uint256 _Zn,
        uint256 _q
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_Zn_Extract.py";
        inputs[2] = vm.toString(_Ln);
        inputs[3] = vm.toString(_Wn);
        inputs[4] = vm.toString(_WIn);
        inputs[5] = vm.toString(_Zn);
        inputs[6] = vm.toString(_q);
        return inputs;
    }

    function _buildFFICalculateHofN(uint Xn, uint Bn, uint Cn, uint C, uint xMin, uint Dv, uint W) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](9);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_h.py";
        inputs[2] = vm.toString(Xn);
        inputs[3] = vm.toString(Bn);
        inputs[4] = vm.toString(Cn);
        inputs[5] = vm.toString(C);
        inputs[6] = vm.toString(xMin);
        inputs[7] = vm.toString(Dv);
        inputs[8] = vm.toString(W);
        return inputs;
    }

    function _buildFFICalculateBeta(BetaParams memory params) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](10);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_beta.py";
        inputs[2] = vm.toString(params.bn);
        inputs[3] = vm.toString(params.Mn);
        inputs[4] = vm.toString(params.cn);
        inputs[5] = vm.toString(params.Xn);
        inputs[6] = vm.toString(params.A);
        inputs[7] = vm.toString(params.B);
        inputs[8] = vm.toString(params.Dv);
        inputs[9] = vm.toString(params.Dn);
        return inputs;
    }

    function _buildFFICalculateAlpha(uint256 bn, uint256 Mn, uint256 cn, uint256 Dv) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_alpha.py";
        inputs[2] = vm.toString(bn);
        inputs[3] = vm.toString(Mn);
        inputs[4] = vm.toString(cn);
        inputs[5] = vm.toString(Dv);
        return inputs;
    }

    function _buildFFICalculateGamma(uint Bn, uint Xn, uint cn, uint Dn, uint A, uint B) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](8);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_gamma.py";
        inputs[2] = vm.toString(Bn);
        inputs[3] = vm.toString(Xn);
        inputs[4] = vm.toString(cn);
        inputs[5] = vm.toString(Dn);
        inputs[6] = vm.toString(A);
        inputs[7] = vm.toString(B);
        return inputs;
    }

    function _buildFFICalculateQofM(uint _A, uint _B, uint _L, uint _xMax, uint _Xn, uint _Dn) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](8);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_q.py";
        inputs[2] = vm.toString(_A);
        inputs[3] = vm.toString(_B);
        inputs[4] = vm.toString(_L);
        inputs[5] = vm.toString(_xMax);
        inputs[6] = vm.toString(_Xn);
        inputs[7] = vm.toString(_Dn);
        return inputs;
    }

    function _buildFFICalculateLiquidityDepositXofN(
        uint256 xMax,
        uint256 q,
        uint256 A,
        uint256 Xn
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_LiquidityDepositXofN.py";
        inputs[2] = vm.toString(xMax);
        inputs[3] = vm.toString(q);
        inputs[4] = vm.toString(A);
        inputs[5] = vm.toString(Xn);
        return inputs;
    }

    function _buildFFICalculateHofNFloat(uint L, uint W, uint phi, uint Zn, uint wInactive) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_h_float.py";
        inputs[2] = vm.toString(L);
        inputs[3] = vm.toString(W);
        inputs[4] = vm.toString(phi);
        inputs[5] = vm.toString(Zn);
        inputs[6] = vm.toString(wInactive);
        return inputs;
    }

    function _buildFFICalculateMultiplier(uint term1, uint term2, uint isDivision) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/multiplier.py";
        inputs[2] = vm.toString(term1);
        inputs[3] = vm.toString(term2);
        inputs[4] = vm.toString(isDivision);
        return inputs;
    }

    function _buildFFICalculateWithdrawMultiplier(
        uint uj,
        uint W,
        uint multiplicand,
        uint isDivision
    ) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "./script/python/ALTBC/calculate_withdraw_multiplier.py";
        inputs[2] = vm.toString(uj);
        inputs[3] = vm.toString(W);
        inputs[4] = vm.toString(multiplicand);
        inputs[5] = vm.toString(isDivision);
        return inputs;
    }

    function _buildFFICalculateRevenueAvailable(uint wj, uint hn, uint r_hat) internal pure returns (string[] memory) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = "script/python/ALTBC/calculate_revenue_available.py";
        inputs[2] = vm.toString(wj);
        inputs[3] = vm.toString(hn);
        inputs[4] = vm.toString(r_hat);
        return inputs;
    }
}
