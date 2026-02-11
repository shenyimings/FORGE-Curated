// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// External imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract ComputeTokenFeeForExactSharesTest is FeeManagerTest {
    function test_computeTokenFeeForExactShares() public {
        uint256 shares = 1 ether;
        uint256 mintTokenFee = 200;
        uint256 mintTreasuryFee = 400;
        uint256 redeemTokenFee = 600;
        uint256 redeemTreasuryFee = 800;

        _setLeverageTokenActionFees(mintTokenFee, redeemTokenFee);
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Mint, mintTreasuryFee);
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Redeem, redeemTreasuryFee);

        (uint256 grossShares, uint256 tokenFee, uint256 treasuryFee) =
            feeManager.exposed_computeFeesForNetShares(leverageToken, shares, ExternalAction.Mint);

        uint256 expectedGrossShares = Math.mulDiv(
            shares, MAX_BPS_SQUARED, (MAX_BPS - mintTokenFee) * (MAX_BPS - mintTreasuryFee), Math.Rounding.Ceil
        );
        assertEq(grossShares, expectedGrossShares);
        assertEq(grossShares, 1.062925170068027211 ether); // 1 ether * 1e8 / ((1e4 - 200) * (1e4 - 400)), rounded up

        uint256 expectedTokenFee = Math.mulDiv(grossShares, mintTokenFee, MAX_BPS, Math.Rounding.Ceil);
        assertEq(tokenFee, expectedTokenFee);
        assertEq(tokenFee, 0.021258503401360545 ether); // 1062925170068027211 * 200 / 1e8, rounded up

        uint256 expectedTreasuryFee = grossShares - tokenFee - shares;
        assertEq(treasuryFee, expectedTreasuryFee);
        assertEq(treasuryFee, 0.041666666666666666 ether); // 1062925170068027211 - 21258503401360545 - 1 ether

        (grossShares, tokenFee, treasuryFee) =
            feeManager.exposed_computeFeesForNetShares(leverageToken, shares, ExternalAction.Redeem);

        expectedGrossShares = Math.mulDiv(
            shares, MAX_BPS_SQUARED, (MAX_BPS - redeemTokenFee) * (MAX_BPS - redeemTreasuryFee), Math.Rounding.Ceil
        );
        assertEq(grossShares, expectedGrossShares);
        assertEq(grossShares, 1.15633672525439408 ether); // 1 ether * 1e8 / ((1e4 - 600) * (1e4 - 800)), rounded up

        expectedTokenFee = Math.mulDiv(grossShares, redeemTokenFee, MAX_BPS, Math.Rounding.Ceil);
        assertEq(tokenFee, expectedTokenFee);
        assertEq(tokenFee, 0.069380203515263645 ether); // 1156336725254394080 * 600 / 1e4, rounded up

        expectedTreasuryFee = grossShares - tokenFee - shares;
        assertEq(treasuryFee, expectedTreasuryFee);
        assertEq(treasuryFee, 0.086956521739130435 ether); // 1156336725254394080 - 69380203515263645 - 1 ether
    }

    function testFuzz_computeTokenFeeForExactShares(
        uint256 shares,
        uint256 mintTokenFee,
        uint256 mintTreasuryFee,
        uint256 redeemTokenFee,
        uint256 redeemTreasuryFee
    ) public {
        shares = bound(shares, 0, type(uint256).max / MAX_BPS_SQUARED);
        mintTokenFee = bound(mintTokenFee, 0, MAX_ACTION_FEE);
        mintTreasuryFee = bound(mintTreasuryFee, 0, MAX_ACTION_FEE);
        redeemTokenFee = bound(redeemTokenFee, 0, MAX_ACTION_FEE);
        redeemTreasuryFee = bound(redeemTreasuryFee, 0, MAX_ACTION_FEE);

        _setLeverageTokenActionFees(mintTokenFee, redeemTokenFee);
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Mint, mintTreasuryFee);
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Redeem, redeemTreasuryFee);

        (uint256 grossShares, uint256 tokenFee, uint256 treasuryFee) =
            feeManager.exposed_computeFeesForNetShares(leverageToken, shares, ExternalAction.Mint);

        uint256 expectedGrossShares = Math.mulDiv(
            shares, MAX_BPS_SQUARED, (MAX_BPS - mintTokenFee) * (MAX_BPS - mintTreasuryFee), Math.Rounding.Ceil
        );
        assertEq(grossShares, expectedGrossShares);

        uint256 expectedTokenFee =
            Math.min(Math.mulDiv(grossShares, mintTokenFee, MAX_BPS, Math.Rounding.Ceil), grossShares - shares);
        assertEq(tokenFee, expectedTokenFee);

        uint256 expectedTreasuryFee = grossShares - tokenFee - shares;
        assertEq(treasuryFee, expectedTreasuryFee);

        (grossShares, tokenFee, treasuryFee) =
            feeManager.exposed_computeFeesForNetShares(leverageToken, shares, ExternalAction.Redeem);

        expectedGrossShares = Math.mulDiv(
            shares, MAX_BPS_SQUARED, (MAX_BPS - redeemTokenFee) * (MAX_BPS - redeemTreasuryFee), Math.Rounding.Ceil
        );
        assertEq(grossShares, expectedGrossShares);

        expectedTokenFee =
            Math.min(Math.mulDiv(grossShares, redeemTokenFee, MAX_BPS, Math.Rounding.Ceil), grossShares - shares);
        assertEq(tokenFee, expectedTokenFee);

        expectedTreasuryFee = grossShares - tokenFee - shares;
        assertEq(treasuryFee, expectedTreasuryFee);
    }
}
