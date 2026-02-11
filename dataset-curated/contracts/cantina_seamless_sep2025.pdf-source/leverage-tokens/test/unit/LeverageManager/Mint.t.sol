// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ActionData, ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract MintTest is LeverageManagerTest {
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

    function test_mint() public {
        // collateral:debt is 2:1
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 10 ether;
        _testMint(shares, 0, SECONDS_ONE_YEAR);
    }

    function test_mint_WithFees() public {
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Mint, 0.05e4); // 5% fee
        _setTreasuryActionFee(ExternalAction.Mint, 0.1e4); // 10% fee

        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee
        feeManager.chargeManagementFee(leverageToken);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 shares = 10 ether;
        _testMint(shares, 0, SECONDS_ONE_YEAR);
    }

    function test_mint_SharesToMintIsZero() public {
        // CR is 3x
        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({collateral: 9, debt: 3, sharesTotalSupply: 3})
        );

        uint256 sharesToMint = 0;
        ActionData memory previewData = leverageManager.previewMint(leverageToken, sharesToMint);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);

        _testMint(sharesToMint, 0, 0);
    }

    function test_mint_IsEmptyLeverageToken() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 0, debt: 0, sharesTotalSupply: 0});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 sharesToMint = 10 ether;
        uint256 collateralToAdd = 20 ether; // 2x CR

        deal(address(collateralToken), address(this), collateralToAdd);
        collateralToken.approve(address(leverageManager), collateralToAdd);

        // Does not revert
        leverageManager.mint(leverageToken, sharesToMint, collateralToAdd);

        LeverageTokenState memory afterState = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(afterState.collateralInDebtAsset, 20 ether); // 1:1 exchange rate, 2x CR
        assertEq(afterState.debt, 10 ether);
        assertEq(afterState.collateralRatio, 2 * _BASE_RATIO());
    }

    function test_mint_ZeroSharesTotalSupplyWithDust() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 3, debt: 1, sharesTotalSupply: 0});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 sharesToMint = 1 ether;
        uint256 expectedCollateralToAdd = 2 ether;
        uint256 expectedDebtToBorrow = 0.666666666666666666 ether; // 3x CR
        uint256 expectedShares = sharesToMint;

        deal(address(collateralToken), address(this), expectedCollateralToAdd);
        collateralToken.approve(address(leverageManager), expectedCollateralToAdd);

        ActionData memory mintData = leverageManager.mint(leverageToken, sharesToMint, expectedCollateralToAdd);

        assertEq(mintData.collateral, expectedCollateralToAdd);
        assertEq(mintData.debt, expectedDebtToBorrow);
        assertEq(mintData.shares, expectedShares);
        assertEq(mintData.tokenFee, 0);
        assertEq(mintData.treasuryFee, 0);

        LeverageTokenState memory afterState = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(afterState.collateralInDebtAsset, expectedCollateralToAdd + beforeState.collateral);
        assertEq(afterState.debt, expectedDebtToBorrow + beforeState.debt); // 1:1 collateral to debt exchange rate, 2x target CR
        assertEq(
            afterState.collateralRatio,
            Math.mulDiv(
                expectedCollateralToAdd + beforeState.collateral,
                _BASE_RATIO(),
                expectedDebtToBorrow + beforeState.debt,
                Math.Rounding.Floor
            )
        );
        assertEq(leverageToken.totalSupply(), beforeState.sharesTotalSupply + expectedShares);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_mint_RevertIf_SlippageIsTooHigh(uint128 collateralSlippage) public {
        uint256 sharesToMint = 10 ether;
        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 10 ether})
        );

        // 10 ether shares will require 20 ether collateral
        collateralSlippage = uint128(bound(collateralSlippage, 1, 20 ether));

        ActionData memory previewData = leverageManager.previewMint(leverageToken, sharesToMint);

        deal(address(collateralToken), address(this), previewData.collateral);
        collateralToken.approve(address(leverageManager), previewData.collateral);

        uint256 maxCollateral = previewData.collateral - collateralSlippage; // Less than previewed

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.SlippageTooHigh.selector, previewData.collateral, maxCollateral)
        );
        leverageManager.mint(leverageToken, sharesToMint, maxCollateral);
    }

    function testFuzz_mint_SharesTotalSupplyGreaterThanZero(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 initialSharesTotalSupply,
        uint128 sharesToMint
    ) public {
        initialCollateral = uint128(bound(initialCollateral, 1, type(uint128).max));
        initialDebtInCollateralAsset =
            initialCollateral == 1 ? 0 : uint128(bound(initialDebtInCollateralAsset, 1, initialCollateral - 1));
        initialSharesTotalSupply = uint128(bound(initialSharesTotalSupply, 1, type(uint128).max));

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: initialCollateral,
                debt: initialDebtInCollateralAsset, // 1:1 exchange rate for this test
                sharesTotalSupply: initialSharesTotalSupply
            })
        );

        // Ensure the collateral being added does not result in overflows due to mocked value sizes
        sharesToMint = uint128(bound(sharesToMint, 1, type(uint96).max));

        uint256 allowedSlippage = _getAllowedCollateralRatioSlippage(
            Math.min(Math.min(initialCollateral, initialDebtInCollateralAsset), initialSharesTotalSupply)
        );
        _testMint(sharesToMint, allowedSlippage, 0);
    }

    function _testMint(uint256 shares, uint256 collateralRatioDeltaRelative, uint256 deltaTime) internal {
        skip(deltaTime);

        LeverageTokenState memory beforeState = leverageManager.getLeverageTokenState(leverageToken);
        uint256 beforeSharesTotalSupply = leverageToken.totalSupply();
        uint256 beforeSharesFeeAdjustedTotalSupply = leverageManager.getFeeAdjustedTotalSupply(leverageToken);

        // The assertion for collateral ratio before and after the mint in this helper only makes sense to use
        // if the leverage token has totalSupply > 0 before mint, as a mint of equity into a leverage token with totalSupply = 0
        // will not respect the current collateral ratio of the leverage token, it just uses the target collateral ratio
        require(beforeSharesTotalSupply != 0, "Shares total supply must be non-zero to use _testMint helper function");

        ActionData memory previewData = leverageManager.previewMint(leverageToken, shares);

        deal(address(collateralToken), address(this), previewData.collateral);
        collateralToken.approve(address(leverageManager), previewData.collateral);

        ActionData memory expectedMintData = ActionData({
            collateral: previewData.collateral,
            debt: previewData.debt,
            shares: previewData.shares,
            tokenFee: previewData.tokenFee,
            treasuryFee: previewData.treasuryFee
        });

        vm.expectEmit(true, true, true, true);
        emit ILeverageManager.Mint(leverageToken, address(this), expectedMintData);
        ActionData memory actualMintData = leverageManager.mint(leverageToken, shares, previewData.collateral);

        assertEq(actualMintData.shares, expectedMintData.shares, "Shares received mismatch with preview");
        assertEq(
            leverageToken.balanceOf(address(this)), actualMintData.shares, "Shares received mismatch with returned data"
        );
        assertEq(
            leverageToken.totalSupply(),
            beforeSharesFeeAdjustedTotalSupply + expectedMintData.shares + expectedMintData.treasuryFee,
            "Shares total supply mismatch, should include accrued management fee, treasury action fee, and shares minted for the mint"
        );
        assertEq(
            leverageToken.balanceOf(treasury),
            beforeSharesFeeAdjustedTotalSupply - beforeSharesTotalSupply + expectedMintData.treasuryFee,
            "Treasury should have received the accrued management fee shares and the treasury action fee shares"
        );
        assertEq(actualMintData.tokenFee, expectedMintData.tokenFee, "LeverageToken fee mismatch");
        assertEq(actualMintData.treasuryFee, expectedMintData.treasuryFee, "Treasury fee mismatch");

        LeverageTokenState memory afterState = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(
            afterState.collateralInDebtAsset,
            beforeState.collateralInDebtAsset + lendingAdapter.convertCollateralToDebtAsset(expectedMintData.collateral),
            "Collateral in leverage token after mint mismatch"
        );
        assertEq(actualMintData.collateral, expectedMintData.collateral, "Collateral added mismatch");
        assertEq(
            afterState.debt, beforeState.debt + expectedMintData.debt, "Debt in leverage token after mint mismatch"
        );
        assertEq(actualMintData.debt, expectedMintData.debt, "Debt borrowed mismatch");
        assertEq(debtToken.balanceOf(address(this)), expectedMintData.debt, "Debt tokens received mismatch");

        assertLe(
            expectedMintData.tokenFee + expectedMintData.treasuryFee,
            previewData.shares,
            "Token fee + treasury fee should be less than or equal to shares"
        );

        if (beforeState.collateralRatio == type(uint256).max) {
            assertLe(afterState.collateralRatio, beforeState.collateralRatio);
        } else {
            assertApproxEqRel(
                afterState.collateralRatio,
                beforeState.collateralRatio,
                collateralRatioDeltaRelative,
                "Collateral ratio after mint mismatch"
            );
            assertGe(
                afterState.collateralRatio,
                beforeState.collateralRatio,
                "Collateral ratio after mint should be greater than or equal to before"
            );
        }
    }
}
