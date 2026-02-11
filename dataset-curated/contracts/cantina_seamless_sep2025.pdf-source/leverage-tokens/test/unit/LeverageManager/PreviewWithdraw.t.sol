// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ActionData, ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract PreviewWithdrawTest is LeverageManagerTest {
    struct FuzzPreviewWithdrawParams {
        uint128 initialCollateral;
        uint128 initialDebt;
        uint128 initialSharesTotalSupply;
        uint256 collateral;
        uint16 fee;
        uint16 managementFee;
        uint256 collateralRatioTarget;
    }

    uint256 private COLLATERAL_RATIO_TARGET;

    function setUp() public override {
        super.setUp();

        COLLATERAL_RATIO_TARGET = 2 * _BASE_RATIO();

        _createNewLeverageToken(
            manager,
            COLLATERAL_RATIO_TARGET,
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: 0
            }),
            address(collateralToken),
            address(debtToken),
            "dummy name",
            "dummy symbol"
        );
    }

    function test_previewWithdraw_WithFee() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee
        feeManager.chargeManagementFee(leverageToken);

        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Redeem, 0.05e4); // 5% fee

        _setTreasuryActionFee(feeManagerRole, ExternalAction.Redeem, 0.1e4); // 10% fee

        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 17.1 ether;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        assertEq(previewData.collateral, 17.1 ether);
        assertEq(previewData.debt, 17.1 ether);
        // 5% fee on gross shares = 20 * 0.05 = 1
        assertEq(previewData.tokenFee, 1 ether);
        // 10% fee on gross shares after token fee applied = (20 - 1) * 0.1 = 1.9
        assertEq(previewData.treasuryFee, 1.9 ether);
        assertEq(previewData.shares, 20 ether);

        skip(SECONDS_ONE_YEAR);

        previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        // Share amounts are increased by ~10% due to management fee diluting share value
        assertEq(previewData.collateral, 17.1 ether);
        assertEq(previewData.debt, 17.1 ether);
        assertEq(previewData.tokenFee, 1.1 ether);
        assertEq(previewData.treasuryFee, 2.09 ether);
        assertEq(previewData.shares, 22 ether);
    }

    function test_previewWithdraw_WithoutFees() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 50 ether;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        assertEq(previewData.collateral, 50 ether);
        assertEq(previewData.debt, 25 ether);
        assertEq(previewData.shares, 50 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function test_PreviewWithdraw_CollateralGtTotalCollateral() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 150 ether;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        assertEq(previewData.collateral, 150 ether);
        assertEq(previewData.debt, 75 ether);
        assertEq(previewData.shares, 150 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewWithdraw_ZeroCollateralZeroDebtNonZeroTotalSupply(
        uint256 collateralToWithdraw,
        uint256 totalSupply
    ) public {
        totalSupply = uint256(bound(totalSupply, 1, type(uint256).max));
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 0, debt: 0, sharesTotalSupply: totalSupply});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = collateralToWithdraw;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        // The initial collateral ratio is used to determine the debt amount in the preview when there is no collateral
        // and no debt.
        uint256 initialCollateralRatio = leverageManager.getLeverageTokenInitialCollateralRatio(leverageToken);
        uint256 expectedDebt = lendingAdapter.convertCollateralToDebtAsset(
            Math.mulDiv(collateral, _BASE_RATIO(), initialCollateralRatio, Math.Rounding.Ceil)
        );

        assertEq(previewData.collateral, collateralToWithdraw);
        assertEq(previewData.debt, expectedDebt);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_PreviewWithdraw_ZeroCollateral_WithoutFees(
        uint128 initialCollateral,
        uint128 initialDebt,
        uint128 initialSharesTotalSupply
    ) public {
        MockLeverageManagerStateForAction memory beforeState = MockLeverageManagerStateForAction({
            collateral: initialCollateral,
            debt: initialDebt,
            sharesTotalSupply: initialSharesTotalSupply
        });

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 0;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_PreviewWithdraw_ZeroCollateral_WithFees(
        uint128 initialCollateral,
        uint128 initialDebt,
        uint128 initialSharesTotalSupply,
        uint16 tokenActionFee,
        uint16 treasuryActionFee
    ) public {
        tokenActionFee = uint16(bound(tokenActionFee, 0, MAX_ACTION_FEE));
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Redeem, tokenActionFee);

        treasuryActionFee = uint16(bound(treasuryActionFee, 0, MAX_ACTION_FEE));
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Redeem, treasuryActionFee);

        MockLeverageManagerStateForAction memory beforeState = MockLeverageManagerStateForAction({
            collateral: initialCollateral,
            debt: initialDebt,
            sharesTotalSupply: initialSharesTotalSupply
        });

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 0;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_PreviewWithdraw_ZeroTotalSupply(uint128 initialCollateral, uint128 initialDebt) public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: initialCollateral, debt: initialDebt, sharesTotalSupply: 0});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 200 ether;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        assertEq(previewData.collateral, collateral);
        assertEq(
            previewData.debt, leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Ceil)
        );
        assertEq(
            previewData.shares, leverageManager.convertCollateralToShares(leverageToken, collateral, Math.Rounding.Ceil)
        );
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewWithdraw_WithFuzzedExchangeRate(uint256 exchangeRate) public {
        exchangeRate = uint256(bound(exchangeRate, 1, 100000e8));
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(exchangeRate);

        uint256 collateral = 100 ether;
        uint256 debt = lendingAdapter.convertCollateralToDebtAsset(collateral) / 2; // 2x LT

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: collateral, debt: debt, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateralToWithdraw = 10 ether;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);

        assertEq(previewData.collateral, 10 ether);
        assertEq(previewData.debt, lendingAdapter.convertCollateralToDebtAsset(10 ether) / 2);
        assertEq(
            previewData.shares, leverageManager.convertCollateralToShares(leverageToken, 10 ether, Math.Rounding.Ceil)
        );
    }

    function testFuzz_PreviewWithdraw(FuzzPreviewWithdrawParams memory params) public {
        params.collateralRatioTarget =
            uint256(bound(params.collateralRatioTarget, _BASE_RATIO() + 1, 10 * _BASE_RATIO()));

        // 0% to 99.99% token action fee
        params.fee = uint16(bound(params.fee, 0, MAX_ACTION_FEE));

        _createNewLeverageToken(
            manager,
            params.collateralRatioTarget,
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: params.fee
            }),
            address(collateralToken),
            address(debtToken),
            "dummy name",
            "dummy symbol"
        );

        // 0% to 100% management fee
        params.managementFee = uint16(bound(params.managementFee, 0, MAX_MANAGEMENT_FEE));
        _setManagementFee(feeManagerRole, leverageToken, params.managementFee);

        // Bound initial debt in collateral asset to be less than or equal to initial collateral (1:1 exchange rate)
        params.initialDebt = uint128(bound(params.initialDebt, 0, params.initialCollateral));

        params.initialSharesTotalSupply = uint128(bound(params.initialSharesTotalSupply, 1, type(uint128).max));

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: params.initialCollateral,
                debt: params.initialDebt, // 1:1 exchange rate for this test
                sharesTotalSupply: params.initialSharesTotalSupply
            })
        );

        uint256 collateralToWithdraw = bound(params.collateral, 0, uint256(params.initialCollateral));

        LeverageTokenState memory prevState = leverageManager.getLeverageTokenState(leverageToken);

        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);

        // Calculate state after action
        uint256 newCollateralRatio = _computeLeverageTokenCRAfterAction(
            params.initialCollateral,
            params.initialDebt,
            previewData.collateral,
            previewData.debt,
            ExternalAction.Redeem
        );
        uint256 newDebt = params.initialDebt - previewData.debt;
        uint256 newCollateral = params.initialCollateral - previewData.collateral;

        // Technically, executing a withdrawal where the previewed shares are greater than the initial shares total supply
        // is not possible and revert. However, the invariants checked in this test should still hold
        uint256 newShares = params.initialSharesTotalSupply > previewData.shares
            ? params.initialSharesTotalSupply - previewData.shares
            : 0;

        {
            uint256 shares =
                leverageManager.convertCollateralToShares(leverageToken, collateralToWithdraw, Math.Rounding.Ceil);
            uint256 debt =
                leverageManager.convertCollateralToDebt(leverageToken, collateralToWithdraw, Math.Rounding.Ceil);
            (uint256 sharesAfterFees, uint256 tokenFee, uint256 treasuryFee) =
                leverageManager.exposed_computeFeesForNetShares(leverageToken, shares, ExternalAction.Redeem);

            // Validate if shares, collateral, debt, and fees are properly calculated and returned
            assertEq(previewData.shares, sharesAfterFees, "Preview shares incorrect");
            assertEq(previewData.collateral, collateralToWithdraw, "Preview collateral incorrect");
            assertEq(previewData.debt, debt, "Preview debt incorrect");
            assertEq(previewData.tokenFee, tokenFee, "Preview token fee incorrect");
            assertEq(previewData.treasuryFee, treasuryFee, "Preview treasury fee incorrect");
        }

        if (previewData.shares == 0) {
            assertEq(
                newCollateralRatio,
                prevState.collateralRatio,
                "Collateral ratio after redeem should be equal to before if zero shares are redeemed"
            );
        } else if (newDebt == 0) {
            assertEq(
                newCollateralRatio,
                type(uint256).max,
                "Collateral ratio after redeem should be equal to type(uint256).max if zero debt is left"
            );
        } else {
            // Below 10 debt, the new collateral ratio can be variable due to low precision.
            // The precision is also dependent on shares because shares are calculated from the collateral
            // withdrawn, then debt is calculated from those shares.
            if (newDebt > 10 && newShares > 10) {
                assertApproxEqRel(
                    newCollateralRatio,
                    prevState.collateralRatio,
                    _getAllowedCollateralRatioSlippage(Math.min(newDebt, newShares)),
                    "Collateral ratio after redeem should be within the allowed slippage"
                );
            }
            assertGe(
                newCollateralRatio,
                prevState.collateralRatio,
                "Collateral ratio after redeem should be greater than or equal to before"
            );
        }

        if (newCollateral == 0) {
            if (params.initialSharesTotalSupply > 0 && params.initialCollateral == 0 && params.initialDebt == 0) {
                assertEq(
                    previewData.collateral,
                    0,
                    "Preview collateral should be zero if initial collateral and initial debt are zero but initial shares total supply is greater than zero"
                );
                assertEq(
                    previewData.debt,
                    0,
                    "Preview debt should be zero if initial collateral and initial debt are zero but initial shares total supply is greater than zero"
                );
            } else {
                assertEq(newShares, 0, "New shares should be zero if new collateral is zero");
                assertEq(newDebt, 0, "New debt should be zero if new collateral is zero");
            }
        }
    }
}
