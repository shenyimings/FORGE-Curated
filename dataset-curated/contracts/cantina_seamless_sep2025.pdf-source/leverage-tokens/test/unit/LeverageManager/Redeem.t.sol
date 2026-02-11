// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ActionData, ExternalAction, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "../LeverageManager/LeverageManager.t.sol";

contract RedeemTest is LeverageManagerTest {
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

    function testFuzz_redeem_WithFees(uint256 shares) public {
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Redeem, 0.05e4); // 5% fee
        _setTreasuryActionFee(ExternalAction.Redeem, 0.05e4); // 5% fee

        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        shares = uint256(bound(shares, 1, 100 ether));
        _testRedeem(shares, 0);
    }

    function testFuzz_redeem_WithoutFees(uint256 shares) public {
        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        shares = uint256(bound(shares, 1, 100 ether));
        _testRedeem(shares, 0);
    }

    function test_redeem_ZeroShares() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        _testRedeem(0, 0);
    }

    function testFuzz_redeem_RevertIf_SlippageTooHigh(uint256 shares, uint256 slippageDelta) public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        shares = bound(shares, 0, 100 ether);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);
        slippageDelta = bound(slippageDelta, 1, type(uint256).max - previewData.collateral);

        _testRedeem(shares, previewData.collateral + slippageDelta);
    }

    function testFuzz_redeem_RevertIf_SharesGreaterThanBalance(uint128 shares) public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        vm.startPrank(address(leverageManager));
        leverageToken.mint(address(this), shares);
        vm.stopPrank();

        uint256 sharesToRedeem = uint256(shares) + 1;

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);

        // Mint debt tokens to sender and approve leverage manager
        debtToken.mint(address(this), previewData.debt);
        debtToken.approve(address(leverageManager), previewData.debt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                leverageToken.balanceOf(address(this)),
                sharesToRedeem
            )
        );
        leverageManager.redeem(leverageToken, sharesToRedeem, 0);
    }

    function testFuzz_redeem(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 sharesTotalSupply,
        uint128 sharesToRedeem,
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

        sharesToRedeem = uint128(bound(sharesToRedeem, 0, sharesTotalSupply));

        uint256 expectedCollateral = leverageManager.previewRedeem(leverageToken, sharesToRedeem).collateral;

        _testRedeem(sharesToRedeem, expectedCollateral);
    }

    function _testRedeem(uint256 sharesToRedeem, uint256 minCollateral) internal {
        // First preview the redemption of shares
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);

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
        bool expectRevertDueToSlippage = previewData.collateral < minCollateral;
        if (expectRevertDueToSlippage) {
            vm.expectRevert(
                abi.encodeWithSelector(ILeverageManager.SlippageTooHigh.selector, previewData.collateral, minCollateral)
            );
        }
        ActionData memory redeemData = leverageManager.redeem(leverageToken, sharesToRedeem, minCollateral);

        if (expectRevertDueToSlippage) {
            return;
        }

        // Verify return values match preview
        assertEq(redeemData.collateral, previewData.collateral);
        assertEq(redeemData.debt, previewData.debt);
        assertEq(redeemData.shares, previewData.shares);
        assertEq(redeemData.tokenFee, previewData.tokenFee);
        assertEq(redeemData.treasuryFee, previewData.treasuryFee);

        // Verify token transfers
        assertEq(collateralToken.balanceOf(address(this)) - collateralBalanceBefore, redeemData.collateral);
        assertEq(debtBalanceBefore - debtToken.balanceOf(address(this)), redeemData.debt);

        // Validate leverage token total supply and balance
        assertEq(leverageToken.totalSupply(), shareTotalSupplyBefore - redeemData.shares + redeemData.treasuryFee);
        assertEq(sharesBalanceBefore - leverageToken.balanceOf(address(this)), redeemData.shares);
        assertEq(leverageToken.balanceOf(address(this)), sharesBalanceBefore - redeemData.shares);

        // Verify that the treasury received the treasury action fee
        assertEq(leverageToken.balanceOf(treasury), redeemData.treasuryFee);

        // Verify that if any collateral is returned, the amount of shares the user lost is non-zero
        if (redeemData.collateral > 0) {
            assertGt(redeemData.shares, 0);
        }

        // Share fees should be less than or equal to the shares redeemed
        assertLe(redeemData.tokenFee + redeemData.treasuryFee, redeemData.shares);

        // Verify the collateral ratio is >= the collateral ratio before the redeem
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(lendingAdapter.getCollateral() * debtBalanceBefore, collateralBalanceBefore * lendingAdapter.getDebt());
    }
}
