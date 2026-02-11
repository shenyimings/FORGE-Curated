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

contract DepositTest is LeverageManagerTest {
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

    function test_deposit() public {
        // collateral:debt is 2:1
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(0.5e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 20 ether;
        _testDeposit(collateral, 0, SECONDS_ONE_YEAR);
    }

    function test_deposit_WithFees() public {
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Mint, 0.05e4); // 5% fee
        _setTreasuryActionFee(ExternalAction.Mint, 0.1e4); // 10% fee

        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee
        feeManager.chargeManagementFee(leverageToken);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 50 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateral = 20 ether;
        _testDeposit(collateral, 0, SECONDS_ONE_YEAR);
    }

    function test_deposit_CollateralToDepositIsZero() public {
        // CR is 3x
        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({collateral: 9, debt: 3, sharesTotalSupply: 3})
        );

        uint256 collateralToDeposit = 0;
        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, collateralToDeposit);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
        assertEq(previewData.tokenFee, 0);
        assertEq(previewData.treasuryFee, 0);

        _testDeposit(collateralToDeposit, 0, 0);
    }

    function test_deposit_IsEmptyLeverageToken() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 0, debt: 0, sharesTotalSupply: 0});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateralToDeposit = 20 ether; // 2x CR

        deal(address(collateralToken), address(this), collateralToDeposit);
        collateralToken.approve(address(leverageManager), collateralToDeposit);

        // Does not revert
        leverageManager.deposit(leverageToken, collateralToDeposit, 0);

        LeverageTokenState memory afterState = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(afterState.collateralInDebtAsset, 20 ether); // 1:1 exchange rate, 2x CR
        assertEq(afterState.debt, 10 ether);
        assertEq(afterState.collateralRatio, 2 * _BASE_RATIO());
    }

    function test_deposit_ZeroSharesTotalSupplyWithDust() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 3, debt: 1, sharesTotalSupply: 0});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 collateralToDeposit = 2 ether;
        uint256 expectedDebtToBorrow = 0.666666666666666666 ether; // 3x CR
        uint256 expectedShares = 1 ether;

        deal(address(collateralToken), address(this), collateralToDeposit);
        collateralToken.approve(address(leverageManager), collateralToDeposit);

        ActionData memory depositData = leverageManager.deposit(leverageToken, collateralToDeposit, expectedShares);

        assertEq(depositData.collateral, collateralToDeposit);
        assertEq(depositData.debt, expectedDebtToBorrow);
        assertEq(depositData.shares, expectedShares);
        assertEq(depositData.tokenFee, 0);
        assertEq(depositData.treasuryFee, 0);

        LeverageTokenState memory afterState = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(afterState.collateralInDebtAsset, collateralToDeposit + beforeState.collateral);
        assertEq(afterState.debt, expectedDebtToBorrow + beforeState.debt); // 1:1 collateral to debt exchange rate, ~3x target CR
        assertEq(
            afterState.collateralRatio,
            Math.mulDiv(
                collateralToDeposit + beforeState.collateral,
                _BASE_RATIO(),
                expectedDebtToBorrow + beforeState.debt,
                Math.Rounding.Floor
            )
        );
        assertEq(leverageToken.totalSupply(), beforeState.sharesTotalSupply + expectedShares);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_deposit_RevertIf_SlippageIsTooHigh(uint256 sharesSlippage) public {
        uint256 collateralToDeposit = 20 ether;
        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({collateral: 100 ether, debt: 50 ether, sharesTotalSupply: 10 ether})
        );

        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, collateralToDeposit);

        deal(address(collateralToken), address(this), previewData.collateral);
        collateralToken.approve(address(leverageManager), previewData.collateral);

        // 20 ether collateral will mint 10 ether shares
        sharesSlippage = uint256(bound(sharesSlippage, 1, type(uint256).max - 10 ether));

        uint256 minShares = previewData.shares + sharesSlippage; // Less than previewed

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.SlippageTooHigh.selector, previewData.shares, minShares)
        );
        leverageManager.deposit(leverageToken, collateralToDeposit, minShares);
    }

    function testFuzz_deposit_SharesTotalSupplyGreaterThanZero(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 initialSharesTotalSupply,
        uint128 collateralToDeposit
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
        collateralToDeposit = uint128(bound(collateralToDeposit, 1, type(uint128).max));

        uint256 allowedSlippage = _getAllowedCollateralRatioSlippage(
            Math.min(Math.min(initialCollateral, initialDebtInCollateralAsset), initialSharesTotalSupply)
        );
        _testDeposit(collateralToDeposit, allowedSlippage, 0);
    }

    function _testDeposit(uint256 collateral, uint256 collateralRatioDeltaRelative, uint256 deltaTime) internal {
        skip(deltaTime);

        LeverageTokenState memory beforeState = leverageManager.getLeverageTokenState(leverageToken);
        uint256 beforeSharesTotalSupply = leverageToken.totalSupply();
        uint256 beforeSharesFeeAdjustedTotalSupply = leverageManager.getFeeAdjustedTotalSupply(leverageToken);

        // The assertion for collateral ratio before and after the deposit in this helper only makes sense to use
        // if the leverage token has totalSupply > 0 before deposit, as a deposit of collateral into a leverage token with totalSupply = 0
        // will not respect the current collateral ratio of the leverage token, it just uses the target collateral ratio
        require(
            beforeSharesTotalSupply != 0, "Shares total supply must be non-zero to use _testDeposit helper function"
        );

        ActionData memory previewData = leverageManager.previewDeposit(leverageToken, collateral);

        deal(address(collateralToken), address(this), previewData.collateral);
        collateralToken.approve(address(leverageManager), previewData.collateral);

        ActionData memory expectedDepositData = ActionData({
            collateral: previewData.collateral,
            debt: previewData.debt,
            shares: previewData.shares,
            tokenFee: previewData.tokenFee,
            treasuryFee: previewData.treasuryFee
        });

        vm.expectEmit(true, true, true, true);
        emit ILeverageManager.Mint(leverageToken, address(this), expectedDepositData);
        ActionData memory actualDepositData = leverageManager.deposit(leverageToken, collateral, previewData.shares);

        assertEq(actualDepositData.shares, expectedDepositData.shares, "Shares received mismatch with preview");
        assertEq(
            leverageToken.balanceOf(address(this)),
            actualDepositData.shares,
            "Shares received mismatch with returned data"
        );
        assertEq(
            leverageToken.totalSupply(),
            beforeSharesFeeAdjustedTotalSupply + expectedDepositData.shares + expectedDepositData.treasuryFee,
            "Shares total supply mismatch, should include accrued management fee, treasury action fee, and shares minted for the mint"
        );
        assertEq(
            leverageToken.balanceOf(treasury),
            beforeSharesFeeAdjustedTotalSupply - beforeSharesTotalSupply + expectedDepositData.treasuryFee,
            "Treasury should have received the accrued management fee shares and the treasury action fee shares"
        );
        assertEq(actualDepositData.tokenFee, expectedDepositData.tokenFee, "LeverageToken fee mismatch");
        assertEq(actualDepositData.treasuryFee, expectedDepositData.treasuryFee, "Treasury fee mismatch");

        LeverageTokenState memory afterState = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(
            afterState.collateralInDebtAsset,
            beforeState.collateralInDebtAsset
                + lendingAdapter.convertCollateralToDebtAsset(expectedDepositData.collateral),
            "Collateral in leverage token after mint mismatch"
        );
        assertEq(actualDepositData.collateral, expectedDepositData.collateral, "Collateral added mismatch");
        assertEq(
            afterState.debt, beforeState.debt + expectedDepositData.debt, "Debt in leverage token after mint mismatch"
        );
        assertEq(actualDepositData.debt, expectedDepositData.debt, "Debt borrowed mismatch");
        assertEq(debtToken.balanceOf(address(this)), expectedDepositData.debt, "Debt tokens received mismatch");

        assertLe(
            expectedDepositData.tokenFee + expectedDepositData.treasuryFee,
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
