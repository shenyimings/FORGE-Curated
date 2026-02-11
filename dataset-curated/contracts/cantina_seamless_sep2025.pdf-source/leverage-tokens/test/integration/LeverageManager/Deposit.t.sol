// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {ActionData, LeverageTokenState, ExternalAction} from "src/types/DataTypes.sol";

contract LeverageManagerDepositTest is LeverageManagerTest {
    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_deposit_NoFee() public {
        uint256 sharesToMint = 10 ether;
        uint256 collateralToAdd = 20 ether;
        uint256 debtToBorrow = 33922_924715; // 33922.924715

        ActionData memory depositData = _deposit(user, collateralToAdd, sharesToMint);

        assertEq(leverageToken.balanceOf(user), depositData.shares);
        assertEq(depositData.shares, sharesToMint);
        assertEq(WETH.balanceOf(user), 0);
        assertEq(USDC.balanceOf(user), debtToBorrow);

        assertEq(morphoLendingAdapter.getCollateral(), collateralToAdd);
        assertGe(morphoLendingAdapter.getDebt(), debtToBorrow);
        assertLe(morphoLendingAdapter.getDebt(), debtToBorrow + 1);
    }

    function testFork_deposit_WithFees() public {
        uint256 treasuryActionFee = 10_00; // 10%
        leverageManager.setTreasuryActionFee(ExternalAction.Mint, treasuryActionFee);

        uint256 tokenActionFee = 10_00; // 10%
        leverageToken = _createNewLeverageToken(BASE_RATIO, 2 * BASE_RATIO, 3 * BASE_RATIO, tokenActionFee, 0);

        uint256 managementFee = 10_00; // 10%
        leverageManager.setManagementFee(leverageToken, managementFee);

        morphoLendingAdapter =
            MorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken)));

        uint256 sharesToMint = 8.1 ether;
        uint256 collateralToAdd = 20 ether;

        ActionData memory depositData = _deposit(user, collateralToAdd, sharesToMint);

        // 10% of equity is for diluting leverage token shares, and 10% of the remaining shares
        // after subtracting the dilution is for the treasury fee (10 * 0.9) * 0.9 = 8.1
        assertEq(leverageToken.balanceOf(user), depositData.shares);
        assertEq(depositData.shares, sharesToMint);
        assertEq(leverageToken.balanceOf(treasury), 0.9 ether);
        assertEq(leverageToken.balanceOf(user) + leverageToken.balanceOf(treasury), leverageToken.totalSupply());
        // Some slight deviation from 10 ether is expected due to interest accrual in morpho and rounding errors
        assertEq(morphoLendingAdapter.getEquityInCollateralAsset(), 9.999999999974771473 ether);

        uint256 collateralRatio = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        assertEq(collateralRatio, 1.999999999970521409e18);

        // One year passes, same mint amount occurs
        skip(SECONDS_ONE_YEAR);

        // CR goes down due to morpho borrow interest
        collateralRatio = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        assertEq(collateralRatio, 1.974502635802161566e18);

        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, collateralToAdd);

        assertEq(previewData.collateral, collateralToAdd);
        // Shares minted is higher than before due to share dilution from management fee and morpho borrow interest
        assertEq(previewData.shares, 8.019 ether);
        assertEq(previewData.tokenFee, 0.99 ether); // 10% of total shares minted (9.9)
        assertEq(previewData.treasuryFee, 0.891 ether); // 10% of total shares minted - token fee (8.91)

        // Preview data is the same after charging management fee but treasury balance of LT increases by 0.9 ether (10% of total supply)
        leverageManager.chargeManagementFee(leverageToken);
        previewData = leverageManager.previewDeposit(leverageToken, collateralToAdd);

        assertEq(previewData.collateral, collateralToAdd);
        assertEq(previewData.shares, 8.019 ether);
        assertEq(previewData.tokenFee, 0.99 ether);
        assertEq(previewData.treasuryFee, 0.891 ether);
        assertEq(leverageToken.balanceOf(treasury), 1.8 ether);

        // Deposit again
        _deposit(user, collateralToAdd, previewData.shares);

        assertEq(leverageToken.balanceOf(user), depositData.shares + previewData.shares);
        assertEq(leverageToken.balanceOf(treasury), 1.8 ether + previewData.treasuryFee);
        assertEq(leverageToken.totalSupply(), leverageToken.balanceOf(user) + leverageToken.balanceOf(treasury));

        uint256 collateralRatioAfter = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        assertGe(collateralRatioAfter, collateralRatio);
        assertEq(collateralRatioAfter, 1.974502635816712955e18);
    }

    function testFuzzFork_deposit(
        uint256 collateralToAddA,
        uint256 collateralToAddB,
        uint256 collateralToAddC,
        uint64 deltaTime
    ) public {
        collateralToAddA = bound(collateralToAddA, 2e9, 100 ether);
        collateralToAddB = bound(collateralToAddB, 2e9, 100 ether);
        collateralToAddC = bound(collateralToAddC, 2e9, 100 ether);
        deltaTime = uint64(bound(deltaTime, 0, 365 days));

        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, collateralToAddA);

        ActionData memory depositDataA = _deposit(user, collateralToAddA, previewData.shares);

        assertEq(depositDataA.shares, previewData.shares);
        assertEq(depositDataA.collateral, previewData.collateral);
        assertEq(depositDataA.debt, previewData.debt);
        assertEq(depositDataA.tokenFee, previewData.tokenFee);
        assertEq(depositDataA.treasuryFee, previewData.treasuryFee);

        skip(deltaTime);

        previewData = leverageManager.previewDeposit(leverageToken, collateralToAddB);

        ActionData memory depositDataB = _deposit(user, collateralToAddB, previewData.shares);

        assertEq(depositDataB.shares, previewData.shares);
        assertEq(depositDataB.collateral, previewData.collateral);
        assertEq(depositDataB.debt, previewData.debt);
        assertEq(depositDataB.tokenFee, previewData.tokenFee);
        assertEq(depositDataB.treasuryFee, previewData.treasuryFee);

        skip(deltaTime);

        previewData = leverageManager.previewDeposit(leverageToken, collateralToAddC);

        ActionData memory depositDataC = _deposit(user, collateralToAddC, previewData.shares);

        assertEq(depositDataC.shares, previewData.shares);
        assertEq(depositDataC.collateral, previewData.collateral);
        assertEq(depositDataC.debt, previewData.debt);
        assertEq(depositDataC.tokenFee, previewData.tokenFee);
        assertEq(depositDataC.treasuryFee, previewData.treasuryFee);

        assertEq(
            leverageManager.getLeverageTokenLendingAdapter(leverageToken).getCollateral(),
            collateralToAddA + collateralToAddB + collateralToAddC
        );
        assertEq(leverageToken.balanceOf(user), depositDataA.shares + depositDataB.shares + depositDataC.shares);
    }
}
