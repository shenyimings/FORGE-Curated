// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ActionData, ExternalAction} from "src/types/DataTypes.sol";
import {PreviewActionTest} from "./PreviewAction.t.sol";

contract PreviewDepositTest is PreviewActionTest {
    function testFuzz_previewDeposit_MatchesPreviewAction(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 sharesTotalSupply,
        uint128 equityToAddInCollateralAsset,
        uint16 treasuryFee
    ) public {
        initialDebtInCollateralAsset = uint128(bound(initialDebtInCollateralAsset, 0, initialCollateral));

        treasuryFee = uint16(bound(treasuryFee, 0, 1e4));
        _setTreasuryActionFee(ExternalAction.Deposit, treasuryFee);

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: initialCollateral,
                debt: initialDebtInCollateralAsset,
                sharesTotalSupply: sharesTotalSupply
            })
        );

        ActionData memory previewActionData =
            leverageManager.exposed_previewAction(leverageToken, equityToAddInCollateralAsset, ExternalAction.Deposit);

        ActionData memory actualPreviewData =
            leverageManager.previewDeposit(leverageToken, equityToAddInCollateralAsset);

        assertEq(
            actualPreviewData.collateral,
            previewActionData.collateral + previewActionData.treasuryFee,
            "Collateral to add mismatch"
        );
        assertEq(actualPreviewData.debt, previewActionData.debt, "Debt to borrow mismatch");
        assertEq(actualPreviewData.shares, previewActionData.shares, "Shares after fee mismatch");
        assertEq(actualPreviewData.tokenFee, previewActionData.tokenFee, "Shares fee mismatch");
        assertEq(actualPreviewData.treasuryFee, previewActionData.treasuryFee, "Treasury fee mismatch");
        assertEq(actualPreviewData.equity, previewActionData.equity, "Equity mismatch");
    }
}
