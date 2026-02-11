// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ActionData, ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract PreviewMintTest is LeverageManagerTest {
    struct FuzzPreviewDepositParams {
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

    function test_previewMint_WithFee() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee

        _setTreasuryActionFee(feeManagerRole, ExternalAction.Mint, 0.1e4); // 10% fee

        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Mint, 0.05e4); // 5% fee

        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 17.1 ether;
        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        assertEq(previewData.collateral, 20 ether);
        assertEq(previewData.debt, 20 ether); // 1:2 exchange rate, 2x CR
        assertEq(previewData.tokenFee, 1 ether); // 5% fee applied on gross shares minted (100 ether * 0.05)
        assertEq(previewData.treasuryFee, 1.9 ether); // 10% fee applied on shares after token fee (95 ether * 0.1)
        assertEq(previewData.shares, 17.1 ether); // 100 ether - 5 ether token fee - 9.5 ether treasury fee

        skip(SECONDS_ONE_YEAR);

        previewData = leverageManager.previewMint(leverageToken, shares);

        // Collateral, debt, and equity amounts are reduced by ~10% due to management fee diluting share value
        assertEq(previewData.collateral, 18.181818181818181819 ether);
        assertEq(previewData.debt, 18.181818181818181819 ether);
        assertEq(previewData.tokenFee, 1 ether);
        assertEq(previewData.treasuryFee, 1.9 ether);
        assertEq(previewData.shares, 17.1 ether);
    }

    function test_previewMint_WithoutFee() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 100 ether;
        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        assertEq(previewData.collateral, 100 ether);
        assertEq(previewData.debt, 50 ether);
        assertEq(previewData.shares, 100 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewMint_ZeroShares(
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
        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewMint_ZeroTotalCollateral(uint128 initialTotalSupply, uint128 initialDebt) public {
        initialTotalSupply = uint128(bound(initialTotalSupply, 1, type(uint128).max));
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 0, debt: initialDebt, sharesTotalSupply: initialTotalSupply});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 100 ether;
        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, shares);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewMint_ZeroTotalDebt(uint128 initialCollateral, uint128 initialTotalSupply) public {
        initialTotalSupply = uint128(bound(initialTotalSupply, 1, type(uint128).max));
        MockLeverageManagerStateForAction memory beforeState = MockLeverageManagerStateForAction({
            collateral: initialCollateral,
            debt: 0,
            sharesTotalSupply: initialTotalSupply
        });

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 100 ether;
        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        assertEq(previewData.collateral, Math.mulDiv(shares, initialCollateral, initialTotalSupply, Math.Rounding.Ceil));
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, shares);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewMint_ZeroTotalSupply(uint128 initialCollateral, uint128 initialDebtInCollateralAsset)
        public
    {
        MockLeverageManagerStateForAction memory beforeState = MockLeverageManagerStateForAction({
            collateral: initialCollateral,
            debt: initialDebtInCollateralAsset,
            sharesTotalSupply: 0
        });

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 100 ether;
        uint256 expectedDebt = leverageManager.convertCollateralToDebt(leverageToken, 200 ether, Math.Rounding.Floor);
        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        assertEq(previewData.collateral, 200 ether);
        assertEq(previewData.debt, expectedDebt);
        assertEq(previewData.shares, 100 ether);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);
    }

    function testFuzz_previewMint(FuzzPreviewDepositParams memory params) public {
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
                mintTokenFee: params.fee,
                redeemTokenFee: 0
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

        if (params.initialCollateral == 0 && params.initialDebt == 0) {
            params.initialSharesTotalSupply = 0;
        } else {
            params.initialSharesTotalSupply = uint128(bound(params.initialSharesTotalSupply, 1, type(uint128).max));
        }

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: params.initialCollateral,
                debt: params.initialDebt, // 1:1 exchange rate for this test
                sharesTotalSupply: params.initialSharesTotalSupply
            })
        );

        uint256 initialEquity =
            params.initialCollateral > params.initialDebt ? params.initialCollateral - params.initialDebt : 0;

        // Bound shares to avoid overflows in LM.convertSharesToEquity
        params.shares =
            initialEquity == 0 ? params.shares : uint128(bound(params.shares, 0, type(uint128).max / initialEquity));

        LeverageTokenState memory prevState = leverageManager.getLeverageTokenState(leverageToken);

        ActionData memory previewData = leverageManager.previewMint(leverageToken, params.shares);

        // Calculate state after action
        uint256 newCollateralRatio = _computeLeverageTokenCRAfterAction(
            params.initialCollateral, params.initialDebt, previewData.collateral, previewData.debt, ExternalAction.Mint
        );

        {
            (uint256 grossShares, uint256 tokenFee, uint256 treasuryFee) =
                leverageManager.exposed_computeFeesForNetShares(leverageToken, params.shares, ExternalAction.Mint);
            uint256 collateral =
                leverageManager.convertSharesToCollateral(leverageToken, grossShares, Math.Rounding.Ceil);
            uint256 debt = leverageManager.convertCollateralToDebt(leverageToken, collateral, Math.Rounding.Floor);

            // Validate if shares, collateral, debt, and fees are properly calculated and returned
            assertEq(previewData.shares, params.shares, "Preview shares incorrect");
            assertEq(previewData.collateral, collateral, "Preview collateral incorrect");
            assertEq(previewData.debt, debt, "Preview debt incorrect");
            assertEq(previewData.tokenFee, tokenFee, "Preview token fee incorrect");
            assertEq(previewData.treasuryFee, treasuryFee, "Preview treasury fee incorrect");
        }

        // If no shares are minted, the mint is a essentially a donation of equity
        if (previewData.shares == 0) {
            if (prevState.collateralRatio != type(uint256).max) {
                assertGe(
                    newCollateralRatio,
                    prevState.collateralRatio,
                    "Collateral ratio after deposit should be greater than or equal to before if zero shares are minted when the strategy has debt (collateral ratio != type(uint256).max)"
                );
                assertApproxEqRel(
                    newCollateralRatio,
                    prevState.collateralRatio,
                    _getAllowedCollateralRatioSlippage(
                        Math.min(
                            Math.min(params.initialDebt, params.initialCollateral), params.initialSharesTotalSupply
                        )
                    ),
                    "Collateral ratio after deposit should be still be within the allowed slippage if zero shares are minted and previous collateral ratio is not type(uint256).max"
                );
            } else {
                assertGe(
                    newCollateralRatio,
                    params.collateralRatioTarget,
                    "Collateral ratio after deposit should be greater than or equal to target if zero shares are minted and previous collateral ratio is type(uint256).max"
                );

                // Below 10 debt, the precision of the new collateral ratio is variable due to rounding down when
                // converting collateral to shares, then rounding down again when converting shares to debt in the
                // deposit preview logic.
                if (params.initialDebt + previewData.debt > 10) {
                    assertApproxEqRel(
                        newCollateralRatio,
                        params.collateralRatioTarget,
                        _getAllowedCollateralRatioSlippage(previewData.collateral),
                        "Collateral ratio after deposit should be still be within the allowed slippage if zero shares are minted, debt is added, and previous collateral ratio is type(uint256).max"
                    );
                }
            }
        } else {
            if (params.initialCollateral == 0 || params.initialDebt == 0) {
                // The mint preview logic first calculates shares from collateral, then debt from shares. When the LT
                // has zero total supply, the precision of the resulting CR is dependent on the amount of collateral added
                // wrt the target CR. In cases where the collateral added is less than the target CR / base ratio, the debt
                // will be zero and the collateral ratio will be type(uint256).max.
                // For example, if the target CR is 6e18 and the collateral added is 5:
                // shares = collateral * (targetCR - baseRatio) / targetCR
                //        = 5 * (6e18 - 1e18) / 6e18
                //        = 4.16666..
                //        = 4 (rounded down)
                // debt = shares * baseRatio / (targetCR - baseRatio)
                //      = 4 * 1e18 / (6e18 - 1e18)
                //      = 0.8
                //      = 0 (rounded down)
                //
                // Now, if instead the target CR is 6e18 and the collateral added is 6:
                // shares = collateral * (targetCR - baseRatio) / targetCR
                //        = 6 * (6e18 - 1e18) / 6e18
                //        = 5
                // debt = shares * baseRatio / (targetCR - baseRatio)
                //      = 5 * 1e18 / (6e18 - 1e18)
                //      = 1
                //      = 1 (rounded down)
                if (
                    params.initialSharesTotalSupply == 0
                        && previewData.collateral
                            >= Math.mulDiv(params.collateralRatioTarget, 1, _BASE_RATIO(), Math.Rounding.Ceil)
                ) {
                    // Precision of new CR wrt the target depends on the amount of shares minted when the strategy is empty
                    assertApproxEqRel(
                        newCollateralRatio,
                        params.collateralRatioTarget,
                        _getAllowedCollateralRatioSlippage(previewData.shares),
                        "Collateral ratio after deposit when there is zero collateral should be within the allowed slippage"
                    );
                    assertGe(
                        newCollateralRatio,
                        params.collateralRatioTarget,
                        "Collateral ratio after deposit when there is zero collateral should be greater than or equal to target"
                    );
                } else if (
                    params.initialSharesTotalSupply == 0
                        && previewData.collateral
                            < Math.mulDiv(params.collateralRatioTarget, 1, _BASE_RATIO(), Math.Rounding.Ceil)
                ) {
                    assertEq(
                        newCollateralRatio,
                        type(uint256).max,
                        "Collateral ratio after deposit should be equal to type(uint256).max if collateral added is less than the CR"
                    );
                } else {
                    if (params.initialDebt + previewData.debt != 0) {
                        assertApproxEqRel(
                            newCollateralRatio,
                            params.collateralRatioTarget,
                            _getAllowedCollateralRatioSlippage(previewData.collateral),
                            "Collateral ratio after deposit should be within the allowed slippage"
                        );
                        assertGe(
                            newCollateralRatio,
                            params.collateralRatioTarget,
                            "Collateral ratio after deposit when there is zero collateral should be greater than or equal to target"
                        );
                    } else {
                        assertEq(
                            newCollateralRatio,
                            type(uint256).max,
                            "Collateral ratio after deposit should be equal to type(uint256).max if debt is zero"
                        );
                    }
                }
            } else {
                assertApproxEqRel(
                    newCollateralRatio,
                    prevState.collateralRatio,
                    _getAllowedCollateralRatioSlippage(
                        Math.min(
                            Math.min(params.initialSharesTotalSupply, params.initialCollateral), params.initialDebt
                        )
                    ),
                    "Collateral ratio after deposit should be within the allowed slippage"
                );
                assertGe(
                    newCollateralRatio,
                    prevState.collateralRatio,
                    "Collateral ratio after deposit should be greater than or equal to before"
                );
            }
        }
    }
}
