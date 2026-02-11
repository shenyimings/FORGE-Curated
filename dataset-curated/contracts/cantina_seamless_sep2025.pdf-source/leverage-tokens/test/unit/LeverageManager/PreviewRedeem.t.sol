// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ActionData, ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract PreviewRedeemTest is LeverageManagerTest {
    struct FuzzPreviewRedeemParams {
        uint128 initialCollateral;
        uint128 initialDebt;
        uint128 initialSharesTotalSupply;
        uint128 shares;
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

    function test_previewRedeem_WithFee() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee
        feeManager.chargeManagementFee(leverageToken);

        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Redeem, 0.05e4); // 5% fee

        _setTreasuryActionFee(feeManagerRole, ExternalAction.Redeem, 0.1e4); // 10% fee

        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 17.1 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 14.6205 ether);
        assertEq(previewData.debt, 14.6205 ether);
        assertEq(previewData.shares, 17.1 ether);
        // 5% fee on shares
        assertEq(previewData.tokenFee, 0.855 ether);
        // 10% fee on shares after token fee applied
        assertEq(previewData.treasuryFee, 1.6245 ether);

        skip(SECONDS_ONE_YEAR);

        previewData = leverageManager.previewRedeem(leverageToken, shares);

        // Collateral, debt, and equity amounts are reduced by ~10% due to management fee diluting share value
        assertEq(previewData.collateral, 13.291363636363636363 ether);
        assertEq(previewData.debt, 13.291363636363636364 ether);
        assertEq(previewData.shares, 17.1 ether);
        assertEq(previewData.tokenFee, 0.855 ether);
        assertEq(previewData.treasuryFee, 1.6245 ether);
    }

    function test_previewRedeem_WithoutFee() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 50 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 50 ether);
        assertEq(previewData.debt, 25 ether);
        assertEq(previewData.shares, 50 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function test_PreviewRedeem_SharesGtTotalSupply() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 150 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 150 ether);
        assertEq(previewData.debt, 75 ether);
        assertEq(previewData.shares, 150 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_PreviewRedeem_ZeroShares_WithoutFees(
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

        uint256 shares = 0;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_PreviewRedeem_ZeroShares_WithFees(
        uint128 initialCollateral,
        uint128 initialDebt,
        uint128 initialSharesTotalSupply,
        uint16 tokenActionFee,
        uint16 treasuryActionFee
    ) public {
        // 0% to 99.99% token action fee
        tokenActionFee = uint16(bound(tokenActionFee, 0, MAX_ACTION_FEE));
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Redeem, tokenActionFee);

        // 0% to 100% management fee
        treasuryActionFee = uint16(bound(treasuryActionFee, 0, MAX_ACTION_FEE));
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Redeem, treasuryActionFee);

        MockLeverageManagerStateForAction memory beforeState = MockLeverageManagerStateForAction({
            collateral: initialCollateral,
            debt: initialDebt,
            sharesTotalSupply: initialSharesTotalSupply
        });

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 0;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_PreviewRedeem_ZeroTotalSupply(uint128 initialCollateral, uint128 initialDebt) public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: initialCollateral, debt: initialDebt, sharesTotalSupply: 0});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 100 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 200 ether);
        assertEq(previewData.debt, 100 ether);
        assertEq(previewData.shares, 100 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);

        previewData = leverageManager.previewRedeem(leverageToken, 0);
        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewRedeem_ZeroCollateralZeroDebtNonZeroTotalSupply(
        uint256 sharesToRedeem,
        uint256 totalSupply
    ) public {
        totalSupply = uint256(bound(totalSupply, 1, type(uint256).max));
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 0, debt: 0, sharesTotalSupply: totalSupply});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = sharesToRedeem;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, sharesToRedeem);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewRedeem_WithFuzzedExchangeRate(uint256 exchangeRate) public {
        exchangeRate = uint256(bound(exchangeRate, 1, 100000e8));
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(exchangeRate);

        uint256 collateral = 100 ether;
        uint256 debt = lendingAdapter.convertCollateralToDebtAsset(collateral) / 2; // 2x LT

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: collateral, debt: debt, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 sharesToRedeem = 10 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);

        assertEq(previewData.collateral, 10 ether);
        assertEq(previewData.debt, lendingAdapter.convertCollateralToDebtAsset(previewData.collateral) / 2);
        assertEq(
            previewData.shares,
            leverageManager.convertCollateralToShares(leverageToken, previewData.collateral, Math.Rounding.Ceil)
        );
    }

    function testFuzz_PreviewRedeem(FuzzPreviewRedeemParams memory params) public {
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

        params.initialSharesTotalSupply = uint128(bound(params.initialSharesTotalSupply, 0, type(uint128).max));

        params.shares = uint128(bound(params.shares, 0, params.initialSharesTotalSupply));

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: params.initialCollateral,
                debt: params.initialDebt, // 1:1 exchange rate for this test
                sharesTotalSupply: params.initialSharesTotalSupply
            })
        );

        LeverageTokenState memory prevState = leverageManager.getLeverageTokenState(leverageToken);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, params.shares);

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
        uint256 newShares = params.initialSharesTotalSupply - previewData.shares;

        {
            (, uint256 tokenFee, uint256 treasuryFee) =
                leverageManager.exposed_computeFeesForGrossShares(leverageToken, params.shares, ExternalAction.Redeem);
            uint256 sharesAfterFees = params.shares - tokenFee - treasuryFee;
            uint256 debt = leverageManager.convertSharesToDebt(leverageToken, sharesAfterFees, Math.Rounding.Ceil);
            uint256 collateral =
                leverageManager.convertSharesToCollateral(leverageToken, sharesAfterFees, Math.Rounding.Floor);

            // Validate if shares, collateral, debt, and fees are properly calculated and returned
            assertEq(previewData.shares, params.shares, "Preview shares incorrect");
            assertEq(previewData.collateral, collateral, "Preview collateral incorrect");
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
            // Below 10 debt, the precision of the new collateral ratio can be variable due to low precision
            if (newDebt > 10) {
                assertApproxEqRel(
                    newCollateralRatio,
                    prevState.collateralRatio,
                    _getAllowedCollateralRatioSlippage(newDebt),
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
