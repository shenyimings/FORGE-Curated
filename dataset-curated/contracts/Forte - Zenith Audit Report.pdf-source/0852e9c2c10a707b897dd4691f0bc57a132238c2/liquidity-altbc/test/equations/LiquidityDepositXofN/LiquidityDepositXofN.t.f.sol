/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import "forge-std/console2.sol";
// import {MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
// import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
// import {LiquidityDepositXofNTestBase} from "test/equations/LiquidityDepositXofN/LiquidityDepositXofNTestBase.sol";
// import {ALTBCDef} from "src/amm/ALTBC.sol";
// import {QofMFuzzTests} from "test/equations/QofM/QofM.t.f.sol";

// /**
//  * @title Test Equation LiqDepositXofn
//  * @author  @oscarsernarosero @cirsteve @Palmerg4
//  */
// contract LiqDepositXofN is LiquidityDepositXofNTestBase {
//     using MathLibs for uint256;
//     using ALTBCEquations for ALTBCDef;
//     QofMFuzzTests public qHelper = new QofMFuzzTests();

//     function testEquations_LiqDepositXofN_CalculateLiqDepositXofN(
//         uint256 Bn,
//         uint256 Mn,
//         uint256 Xn,
//         uint256 cn,
//         uint Dv,
//         uint256 A,
//         uint256 B
//     ) public {
//         vm.skip(true);
//         Bn = bound(Bn, Slower, Supper);
//         Mn = bound(Mn, Xlower, Xupper);
//         Xn = bound(Xn, Xlower, Xupper);
//         cn = bound(cn, cLower, cUpper);
//         Dv = bound(Dv, DvLower, DvUpper);
//         A = bound(A, 0, Xn);
//         B = bound(B, 0, Mn * cn);
//         B = B / MathLibs.WAD ** 2;

//         altbc.maxXTokenSupply = Mn;

//         // This is done simply to reuse the revert checks when generating q
//         (uint256 q, ) = qHelper.calculateQTestHelper(Bn, Mn, Xn, cn, Dv, A, B);

//         string[] memory inputs = _buildFFICalculateLiquidityDepositXofN(Mn, q, A, Xn);
//         bytes memory res = vm.ffi(inputs);
//         uint256 pyVal = abi.decode(res, (uint256));

//         uint256 solVal = altbc.liquidityDepositCalculateXn(q, A, Xn);

//         assertEq(solVal, pyVal);
//     }
// }
