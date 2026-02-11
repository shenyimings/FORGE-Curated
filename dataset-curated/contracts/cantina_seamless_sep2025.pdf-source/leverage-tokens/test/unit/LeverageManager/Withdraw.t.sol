// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ActionData, ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract WithdrawTest is LeverageManagerTest {
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

    function testFuzz_withdraw_WithFees(uint256 collateral) public {
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Redeem, 0.05e4); // 5% fee
        _setTreasuryActionFee(ExternalAction.Redeem, 0.1e4); // 10% fee

        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 maxCollateralAfterFees = 200 ether * (MAX_BPS - 0.05e4) * (MAX_BPS - 0.1e4) / MAX_BPS_SQUARED;
        collateral = uint256(bound(collateral, 1, maxCollateralAfterFees));

        _testWithdraw(collateral, type(uint256).max);
    }

    function testFuzz_withdraw_WithoutFees(uint256 collateral) public {
        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        collateral = uint256(bound(collateral, 1, 200 ether));
        _testWithdraw(collateral, type(uint256).max);
    }

    function test_withdraw_ZeroCollateral() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        _testWithdraw(0, 0);
    }

    function testFuzz_withdraw_RevertIf_SlippageTooHigh(uint256 collateral, uint256 slippageDelta) public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        collateral = uint256(bound(collateral, 1, 200 ether));

        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);
        vm.assume(previewData.shares > 0);

        slippageDelta = uint256(bound(slippageDelta, 1, previewData.shares));

        _testWithdraw(collateral, previewData.shares - slippageDelta);
    }

    function test_withdraw_RevertIf_SharesGreaterThanBalance() public {
        uint256 shares = 100 ether;

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: shares});

        _prepareLeverageManagerStateForAction(beforeState);

        vm.startPrank(address(leverageManager));
        leverageToken.burn(address(1), shares - 1);
        leverageToken.mint(address(this), shares - 1);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                leverageToken.balanceOf(address(this)),
                shares
            )
        );
        leverageManager.withdraw(leverageToken, 200 ether, type(uint256).max);
    }

    function testFuzz_withdraw(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 sharesTotalSupply,
        uint256 collateral,
        uint16 tokenFee,
        uint16 treasuryFee,
        uint256 collateralRatioTarget
    ) public {
        collateralRatioTarget = uint256(bound(collateralRatioTarget, _BASE_RATIO() + 1, 10 * _BASE_RATIO()));

        tokenFee = uint16(bound(tokenFee, 0, MAX_ACTION_FEE));

        _createNewLeverageToken(
            manager,
            collateralRatioTarget,
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: tokenFee
            }),
            address(collateralToken),
            address(debtToken),
            "dummy name",
            "dummy symbol"
        );

        treasuryFee = uint16(bound(treasuryFee, 0, MAX_ACTION_FEE));
        _setTreasuryActionFee(ExternalAction.Redeem, treasuryFee);

        initialCollateral =
            uint128(bound(initialCollateral, 0, type(uint128).max / ((MAX_BPS - tokenFee) * (MAX_BPS - treasuryFee))));

        // Bound debt to be lower than collateral asset and share total supply to be greater than 0 otherwise redeem can not work
        initialDebtInCollateralAsset = uint128(bound(initialDebtInCollateralAsset, 0, initialCollateral));
        sharesTotalSupply = uint128(bound(sharesTotalSupply, 1, type(uint128).max));

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: initialCollateral,
                debt: initialDebtInCollateralAsset,
                sharesTotalSupply: sharesTotalSupply
            })
        );

        uint256 maxCollateral = sharesTotalSupply * (MAX_BPS - tokenFee) * (MAX_BPS - treasuryFee) / MAX_BPS_SQUARED
            * initialCollateral / sharesTotalSupply;
        collateral = bound(collateral, 0, maxCollateral);

        uint256 expectedShares = leverageManager.previewWithdraw(leverageToken, collateral).shares;

        _testWithdraw(collateral, expectedShares);
    }

    function _testWithdraw(uint256 collateral, uint256 maxShares) internal {
        // First preview the redemption of shares
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);

        uint256 shareTotalSupplyBefore = leverageToken.totalSupply();

        // This needs to be done this way because initial mock state mints total supply to address(1)
        // In order to keep the same total supply we need to burn and mint the same amount of shares
        vm.startPrank(address(leverageManager));
        leverageToken.burn(address(1), previewData.shares);
        leverageToken.mint(address(this), previewData.shares);
        vm.stopPrank();

        // Mint debt tokens to sender and approve leverage manager
        debtToken.mint(address(this), previewData.debt);
        debtToken.approve(address(leverageManager), previewData.debt);

        uint256 collateralBalanceBefore = collateralToken.balanceOf(address(this));
        uint256 debtBalanceBefore = debtToken.balanceOf(address(this));
        uint256 sharesBalanceBefore = leverageToken.balanceOf(address(this));

        // Execute redemption
        bool expectRevertDueToSlippage = previewData.shares > maxShares;
        if (expectRevertDueToSlippage) {
            vm.expectRevert(
                abi.encodeWithSelector(ILeverageManager.SlippageTooHigh.selector, previewData.shares, maxShares)
            );
        }
        ActionData memory withdrawData = leverageManager.withdraw(leverageToken, collateral, maxShares);

        if (expectRevertDueToSlippage) {
            return;
        }

        // Verify return values match preview
        assertEq(withdrawData.collateral, previewData.collateral);
        assertEq(withdrawData.debt, previewData.debt);
        assertEq(withdrawData.shares, previewData.shares);
        assertEq(withdrawData.tokenFee, previewData.tokenFee);
        assertEq(withdrawData.treasuryFee, previewData.treasuryFee);

        // Verify token transfers
        assertEq(collateralToken.balanceOf(address(this)) - collateralBalanceBefore, withdrawData.collateral);
        assertEq(debtBalanceBefore - debtToken.balanceOf(address(this)), withdrawData.debt);

        // Validate leverage token total supply and balance
        assertEq(leverageToken.totalSupply(), shareTotalSupplyBefore - withdrawData.shares + withdrawData.treasuryFee);
        assertEq(sharesBalanceBefore - leverageToken.balanceOf(address(this)), withdrawData.shares);
        assertEq(leverageToken.balanceOf(address(this)), sharesBalanceBefore - withdrawData.shares);

        // Verify that the treasury received the treasury action fee
        assertEq(leverageToken.balanceOf(treasury), withdrawData.treasuryFee);

        // Verify that if any collateral is returned, the amount of shares the user lost is non-zero
        if (withdrawData.collateral > 0) {
            assertGt(withdrawData.shares, 0);
        }

        // Share fees should be less than or equal to the shares redeemed
        assertLe(withdrawData.tokenFee + withdrawData.treasuryFee, withdrawData.shares);

        // Verify the collateral ratio is >= the collateral ratio before the redeem
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(lendingAdapter.getCollateral() * debtBalanceBefore, collateralBalanceBefore * lendingAdapter.getDebt());
    }
}
