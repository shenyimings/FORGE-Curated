// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// Forge imports
import {stdMath} from "forge-std/StdMath.sol";

// Dependency imports
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ExternalAction, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerHandler} from "test/invariant/handlers/LeverageManagerHandler.t.sol";
import {InvariantTestBase} from "test/invariant/InvariantTestBase.t.sol";

contract RedeemInvariants is InvariantTestBase {
    function invariant_redeem() public view {
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore =
            leverageManagerHandler.getLeverageTokenStateBefore();
        if (stateBefore.actionType != LeverageManagerHandler.ActionType.Redeem) {
            return;
        }

        LeverageManagerHandler.RedeemActionData memory redeemData =
            abi.decode(stateBefore.actionData, (LeverageManagerHandler.RedeemActionData));
        IMorphoLendingAdapter lendingAdapter =
            IMorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(redeemData.leverageToken)));

        (,, address oracle,,) = lendingAdapter.marketParams();

        // Check if lendingAdapter.convertCollateralToDebtAsset(total collateral) will overflow. If it does,
        // LeverageManager.getLeverageTokenState will overflow when calculating collateral ratio.
        // Note: Redeems can still occur if ILendingAdapter.convertCollateralToDebtAsset(leverageToken collateral) overflows,
        //       because the logic in LeverageManager does not convert collateral to debt during a redeem.
        if (type(uint256).max / IOracle(oracle).price() >= lendingAdapter.getCollateral()) {
            LeverageTokenState memory stateAfter = leverageManager.getLeverageTokenState(redeemData.leverageToken);

            _assertSharesInvariants(lendingAdapter, redeemData, stateBefore, stateAfter);
            _assertCollateralRatioInvariants(lendingAdapter, redeemData, stateBefore, stateAfter);
        }
    }

    function _assertSharesInvariants(
        ILendingAdapter lendingAdapter,
        LeverageManagerHandler.RedeemActionData memory redeemData,
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageTokenState memory stateAfter
    ) internal view {
        _assertRemainingSharesValue(stateBefore, redeemData, stateAfter);
        _assertTotalSupplyRedeemedEqualsTotalEquity(lendingAdapter, redeemData, stateBefore, stateAfter);
    }

    function _assertRemainingSharesValue(
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageManagerHandler.RedeemActionData memory redeemData,
        LeverageTokenState memory stateAfter
    ) internal view {
        uint256 totalSupplyAfter = redeemData.leverageToken.totalSupply();

        if (totalSupplyAfter != 0) {
            uint256 totalSupplyAfterValueBeforeRedeem = Math.mulDiv(
                totalSupplyAfter, stateBefore.equityInCollateralAsset, stateBefore.totalSupply, Math.Rounding.Floor
            );
            uint256 totalSupplyAfterValueAfterRedeem =
                _convertToAssets(redeemData.leverageToken, totalSupplyAfter, Math.Rounding.Floor);

            assertGe(
                totalSupplyAfterValueAfterRedeem,
                totalSupplyAfterValueBeforeRedeem,
                _getRedeemInvariantDescriptionString(
                    "The value of the remaining shares after a redeem must be greater than or equal to their value before the redeem due to rounding and fees.",
                    stateBefore,
                    stateAfter,
                    redeemData
                )
            );
        }

        if (totalSupplyAfter == stateBefore.totalSupply) {
            assertEq(
                stateBefore.equityInDebtAsset,
                stateAfter.equity,
                _getRedeemInvariantDescriptionString(
                    "The equity in the LT must be the same before and after the redeem if no shares were burned (and thus share value as well).",
                    stateBefore,
                    stateAfter,
                    redeemData
                )
            );
        }
    }

    function _assertTotalSupplyRedeemedEqualsTotalEquity(
        ILendingAdapter lendingAdapter,
        LeverageManagerHandler.RedeemActionData memory redeemData,
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageTokenState memory stateAfter
    ) internal view {
        uint256 totalSupplyAfter = redeemData.leverageToken.totalSupply();
        uint256 sharesRedeemed = stateBefore.totalSupply - totalSupplyAfter;

        if (totalSupplyAfter == 0 && sharesRedeemed != 0) {
            assertEq(
                lendingAdapter.getEquityInCollateralAsset(),
                0,
                _getRedeemInvariantDescriptionString(
                    "When there are no shares remaining after the redeem, all equity must have been redeemed and thus there must be no equity remaining in the LT.",
                    stateBefore,
                    stateAfter,
                    redeemData
                )
            );
        }
    }

    function _assertCollateralRatioInvariants(
        ILendingAdapter lendingAdapter,
        LeverageManagerHandler.RedeemActionData memory redeemData,
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageTokenState memory stateAfter
    ) internal view {
        uint256 totalSupplyAfter = redeemData.leverageToken.totalSupply();

        // If zero shares were burned, or zero equity was passed to the redeem function, strategy collateral ratio should not change
        if (stateBefore.totalSupply == totalSupplyAfter || redeemData.equityInCollateralAsset == 0) {
            assertEq(
                stateBefore.collateralRatio,
                stateAfter.collateralRatio,
                "Invariant Violated: Collateral ratio should not change if zero shares were burnt or zero equity was passed to the redeem function."
            );
        } else {
            uint256 collateralAfter = lendingAdapter.getCollateral();
            if (
                stateBefore.debt != 0 && stateBefore.collateral != 0
                    && type(uint256).max / stateBefore.debt <= collateralAfter
                    && type(uint256).max / stateBefore.collateral <= stateAfter.debt
            ) {
                // Verify the collateral ratio is >= the collateral ratio before the redeem
                // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
                // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
                // ratios
                bool isCollateralRatioGe =
                    collateralAfter * stateBefore.debt >= stateBefore.collateral * stateAfter.debt;
                assertTrue(
                    isCollateralRatioGe,
                    _getRedeemInvariantDescriptionString(
                        string.concat(
                            "Collateral ratio after redeem must be greater than or equal to the collateral ratio before the redeem.",
                            " collateralAfter * stateBefore.debt: ",
                            Strings.toString(collateralAfter * stateBefore.debt),
                            " stateBefore.collateral * stateAfter.debt: ",
                            Strings.toString(stateBefore.collateral * stateAfter.debt)
                        ),
                        stateBefore,
                        stateAfter,
                        redeemData
                    )
                );
            }

            if (stateAfter.debt != 0) {
                _assertCollateralRatioChangeWithinAllowedSlippage(lendingAdapter, stateBefore, stateAfter, redeemData);
            } else {
                assertEq(
                    stateAfter.collateralRatio,
                    type(uint256).max,
                    _getRedeemInvariantDescriptionString(
                        "Collateral ratio after redeeming all debt should be max uint256.",
                        stateBefore,
                        stateAfter,
                        redeemData
                    )
                );
            }
        }
    }

    function _assertCollateralRatioChangeWithinAllowedSlippage(
        ILendingAdapter lendingAdapter,
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageTokenState memory stateAfter,
        LeverageManagerHandler.RedeemActionData memory redeemData
    ) internal view {
        uint256 collateralAfter = lendingAdapter.getCollateral();
        uint256 debtInCollateralAsset = lendingAdapter.convertDebtToCollateralAsset(stateAfter.debt);
        uint256 collateralRatioUsingDebtNormalized = debtInCollateralAsset > 0
            ? Math.mulDiv(collateralAfter, BASE_RATIO, debtInCollateralAsset, Math.Rounding.Floor)
            : type(uint256).max;

        uint256 minCollateral = Math.min(stateBefore.collateral, collateralAfter);
        uint256 minDebt = Math.min(stateBefore.debt, stateAfter.debt);

        uint256 allowedSlippage = _getAllowedCollateralRatioSlippage(Math.min(minDebt, minCollateral));

        bool isCollateralRatioWithinAllowedSlippage = stdMath.percentDelta(
            stateAfter.collateralRatio, stateBefore.collateralRatio
        ) <= allowedSlippage
            || stdMath.percentDelta(collateralRatioUsingDebtNormalized, stateBefore.collateralRatioUsingDebtNormalized)
                <= allowedSlippage;

        assertTrue(
            isCollateralRatioWithinAllowedSlippage,
            _getRedeemInvariantDescriptionString(
                "Collateral ratio after a redeem must be equal to the collateral ratio before the redeem, within the allowed slippage.",
                stateBefore,
                stateAfter,
                redeemData
            )
        );
    }

    function _getRedeemInvariantDescriptionString(
        string memory invariantDescription,
        LeverageManagerHandler.LeverageTokenStateData memory stateBefore,
        LeverageTokenState memory stateAfter,
        LeverageManagerHandler.RedeemActionData memory redeemData
    ) internal pure returns (string memory) {
        return string.concat(
            "Invariant Violated: ",
            invariantDescription,
            _getStateBeforeDebugString(stateBefore),
            _getStateAfterDebugString(stateAfter),
            _getRedeemDataDebugString(redeemData)
        );
    }

    function _getRedeemDataDebugString(LeverageManagerHandler.RedeemActionData memory redeemData)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            " redeemData.leverageToken: ",
            Strings.toHexString(address(redeemData.leverageToken)),
            " redeemData.equityInCollateralAsset: ",
            Strings.toString(redeemData.equityInCollateralAsset),
            " redeemData.equityInDebtAsset: ",
            Strings.toString(redeemData.equityInDebtAsset)
        );
    }
}
