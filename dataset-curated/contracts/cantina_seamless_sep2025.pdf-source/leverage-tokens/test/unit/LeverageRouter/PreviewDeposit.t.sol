// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";
import {MockLeverageManager} from "../mock/MockLeverageManager.sol";

contract PreviewDepositTest is LeverageRouterTest {
    function testFuzz_previewDeposit_ZeroCollateralZeroDebt(
        uint256 collateralFromSender,
        uint256 initialCollateralRatio
    ) public {
        initialCollateralRatio = bound(initialCollateralRatio, leverageManager.BASE_RATIO() + 1, type(uint256).max);
        collateralFromSender = bound(collateralFromSender, 0, type(uint256).max / initialCollateralRatio);

        lendingAdapter.mockCollateral(0);
        lendingAdapter.mockDebt(0);
        leverageManager.setLeverageTokenInitialCollateralRatio(leverageToken, initialCollateralRatio);

        uint256 expectedCollateral = Math.mulDiv(
            collateralFromSender,
            initialCollateralRatio,
            initialCollateralRatio - leverageManager.BASE_RATIO(),
            Math.Rounding.Ceil
        );

        // Since we are mocking the leverageManager previewDeposit call, we only really care about the returned collateral
        leverageManager.setMockPreviewDepositData(
            MockLeverageManager.PreviewDepositParams({leverageToken: leverageToken, collateral: expectedCollateral}),
            MockLeverageManager.MockPreviewDepositData({
                collateral: expectedCollateral,
                debt: 0,
                shares: 0,
                tokenFee: 0,
                treasuryFee: 0
            })
        );
        assertEq(leverageRouter.previewDeposit(leverageToken, collateralFromSender).collateral, expectedCollateral);
    }

    function testFuzz_previewDeposit_NonZeroCollateralOrNonZeroDebt_MaxCollateralRatio(
        uint256 collateralFromSender,
        uint256 collateral
    ) public {
        collateral = bound(collateral, 1, type(uint256).max);

        lendingAdapter.mockCollateral(collateral);

        // Only the collateral ratio returned by LeverageManager.getLeverageTokenState() is relevant for this test
        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({collateralRatio: type(uint256).max, debt: 0, equity: 0, collateralInDebtAsset: 0})
        );

        // Since we are mocking the leverageManager previewDeposit call, we only really care about the returned collateral
        leverageManager.setMockPreviewDepositData(
            MockLeverageManager.PreviewDepositParams({leverageToken: leverageToken, collateral: collateralFromSender}),
            MockLeverageManager.MockPreviewDepositData({
                collateral: collateralFromSender,
                debt: 0,
                shares: 0,
                tokenFee: 0,
                treasuryFee: 0
            })
        );
        assertEq(leverageRouter.previewDeposit(leverageToken, collateralFromSender).collateral, collateralFromSender);
    }

    function testFuzz_previewDeposit_NonZeroCollateralOrNonZeroDebt_NonMaxCollateralRatio(
        uint256 collateralFromSender,
        uint256 collateral,
        uint256 debt,
        uint256 collateralRatio
    ) public {
        collateral = bound(collateral, 0, type(uint256).max);
        debt = bound(debt, 0, type(uint256).max);
        vm.assume(debt > 0 || collateral > 0);

        collateralRatio = bound(collateralRatio, leverageManager.BASE_RATIO() + 1, type(uint256).max - 1);
        collateralFromSender = bound(collateralFromSender, 0, type(uint256).max / collateralRatio);

        lendingAdapter.mockCollateral(collateral);
        lendingAdapter.mockDebt(debt);

        // Only the collateral ratio returned by LeverageManager.getLeverageTokenState() is relevant for this test
        leverageManager.setLeverageTokenState(
            leverageToken,
            LeverageTokenState({collateralRatio: collateralRatio, debt: debt, equity: 0, collateralInDebtAsset: 0})
        );

        uint256 expectedCollateral = Math.mulDiv(
            collateralFromSender, collateralRatio, collateralRatio - leverageManager.BASE_RATIO(), Math.Rounding.Ceil
        );

        // Since we are mocking the leverageManager previewDeposit call, we only really care about the returned collateral
        leverageManager.setMockPreviewDepositData(
            MockLeverageManager.PreviewDepositParams({leverageToken: leverageToken, collateral: expectedCollateral}),
            MockLeverageManager.MockPreviewDepositData({
                collateral: expectedCollateral,
                debt: 0,
                shares: 0,
                tokenFee: 0,
                treasuryFee: 0
            })
        );
        assertEq(leverageRouter.previewDeposit(leverageToken, collateralFromSender).collateral, expectedCollateral);
    }
}
