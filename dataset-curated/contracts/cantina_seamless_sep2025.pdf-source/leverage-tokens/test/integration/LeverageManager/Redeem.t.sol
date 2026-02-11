// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IOracle} from "@morpho-blue/interfaces/IOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {ActionData, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";

contract LeverageManagerRedeemTest is LeverageManagerTest {
    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_redeem_NoFee() public {
        uint256 sharesToMint = 10 ether;
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        LeverageTokenState memory stateBefore = getLeverageTokenState();
        uint256 collateralBefore = morphoLendingAdapter.getCollateral();

        uint256 sharesToRedeem = 5 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        _redeem(user, sharesToRedeem, previewData.collateral, previewData.debt);

        LeverageTokenState memory stateAfter = getLeverageTokenState();

        // Ensure that collateral ratio is the same (with some rounding error)
        // Verify the collateral ratio is >= the collateral ratio before the redeem
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(morphoLendingAdapter.getCollateral() * stateBefore.debt, collateralBefore * stateAfter.debt);

        assertEq(stateAfter.debt, stateBefore.debt - previewData.debt);
        assertEq(WETH.balanceOf(user), previewData.collateral);
    }

    function testFork_redeem_ZeroAmount() public {
        uint256 sharesToMint = 10 ether;
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, 0);
        _redeem(user, 0, previewData.collateral, previewData.debt);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
    }

    function testFork_redeem_FullRedeem() public {
        (,, address oracle,,) = morphoLendingAdapter.marketParams();
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(4000e24));

        uint256 shares = 10 ether;
        _mint(user, shares, type(uint256).max);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);
        _redeem(user, shares, previewData.collateral, previewData.debt);

        // Validate that all shares are burned
        assertEq(leverageToken.totalSupply(), 0);

        // Validate that almost all collateral is redeemed, we round down collateral to redeem so dust can be left
        assertGe(morphoLendingAdapter.getCollateral(), 0);
        assertLe(morphoLendingAdapter.getCollateral(), 2);

        // Validate that entire debt is repaid successfully
        assertEq(morphoLendingAdapter.getDebt(), 0);
    }

    function testFork_redeem_MockPrice() public {
        // Mock ETH price to be 4000 USDC
        (,, address oracle,,) = morphoLendingAdapter.marketParams();
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(4000e24));

        uint256 sharesToMint = 10 ether;
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        LeverageTokenState memory stateBefore = getLeverageTokenState();
        uint256 collateralBefore = morphoLendingAdapter.getCollateral();
        assertEq(stateBefore.collateralRatio, 1999999999950000000); // ~2x CR

        uint256 collateralBeforeRedeem = morphoLendingAdapter.getCollateral();

        uint256 sharesToRedeem = sharesToMint / 2;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        _redeem(user, sharesToRedeem, previewData.collateral, previewData.debt);

        LeverageTokenState memory stateAfter = getLeverageTokenState();
        uint256 collateralAfterRedeem = morphoLendingAdapter.getCollateral();

        // Ensure that collateral ratio is the same (with some rounding error)
        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);
        // Verify the collateral ratio is >= the collateral ratio before the redeem
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(morphoLendingAdapter.getCollateral() * stateBefore.debt, collateralBefore * stateAfter.debt);
        assertEq(stateAfter.collateralRatio, 2000000000000000000);

        // Ensure that after redeem debt and collateral is 50% of what was initially after mint
        assertEq(stateAfter.debt, 20000e6); // 20000 USDC
        assertEq(collateralAfterRedeem, collateralBeforeRedeem / 2);

        assertEq(WETH.balanceOf(user), previewData.collateral);
    }

    function testFork_redeem_PriceChangedBetweenRedeems_CollateralRatioDoesNotChange() public {
        uint256 sharesToMint = 10 ether;
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        // Mock ETH price to be 4000 USDC
        (,, address oracle,,) = morphoLendingAdapter.marketParams();
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(4000e24));

        LeverageTokenState memory stateBefore = getLeverageTokenState();
        uint256 collateralBefore = morphoLendingAdapter.getCollateral();
        assertEq(stateBefore.collateralRatio, 2358287225224640032); // ~2x CR

        uint256 sharesToRedeem = 5 ether;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        _redeem(user, sharesToRedeem, previewData.collateral, previewData.debt);

        LeverageTokenState memory stateAfter = getLeverageTokenState();

        // Ensure that collateral ratio is the same (with some rounding error)
        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);
        // Verify the collateral ratio is >= the collateral ratio before the redeem
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(morphoLendingAdapter.getCollateral() * stateBefore.debt, collateralBefore * stateAfter.debt);
        assertEq(stateAfter.collateralRatio, 2358287225224640032);

        assertEq(WETH.balanceOf(user), previewData.collateral);
    }

    function testFork_redeem_FullRedeemComparedToPartialRedeem() public {
        // Mint some assets initially
        uint256 sharesToMint = 10 ether;
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        // Redeem everything
        ActionData memory previewDataAfterMint = leverageManager.previewRedeem(leverageToken, sharesToMint);
        _redeem(user, sharesToMint, previewDataAfterMint.collateral, previewDataAfterMint.debt);

        // Mint again to create the same scenario
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        // Redeem half of it
        uint256 sharesToRedeem = sharesToMint / 2;
        ActionData memory previewDataFirstTime = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        _redeem(user, sharesToRedeem, previewDataFirstTime.collateral, previewDataFirstTime.debt);

        // Redeem the rest
        ActionData memory previewDataSecondTime = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        _redeem(user, sharesToRedeem, previewDataSecondTime.collateral, previewDataSecondTime.debt);

        // Validate that in both cases we get the same amount of collateral and debt
        assertEq(previewDataFirstTime.collateral + previewDataSecondTime.collateral, previewDataAfterMint.collateral);
        assertEq(previewDataFirstTime.debt + previewDataSecondTime.debt, previewDataAfterMint.debt);

        // Validate that collateral token is properly transferred to user
        assertEq(WETH.balanceOf(user), previewDataFirstTime.collateral + previewDataSecondTime.collateral);
        assertLe(previewDataAfterMint.collateral, 2 * sharesToMint);
    }

    function testFork_redeem_withFee() public {
        uint256 treasuryActionFee = 10_00; // 10%
        leverageManager.setTreasuryActionFee(ExternalAction.Redeem, treasuryActionFee); // 10%

        uint256 tokenActionFee = 10_00; // 10%
        leverageToken =
            _createNewLeverageToken(BASE_RATIO, 2 * BASE_RATIO, 3 * BASE_RATIO, tokenActionFee, tokenActionFee);

        uint256 managementFee = 10_00; // 10%
        leverageManager.setManagementFee(leverageToken, managementFee);

        morphoLendingAdapter =
            MorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken)));

        uint256 sharesToMint = 10 ether;
        _mint(user, sharesToMint, leverageManager.previewMint(leverageToken, sharesToMint).collateral);

        // 10% of equity goes to share dilution (token action fee), so 9 ether shares are minted instead of 10 ether
        assertEq(leverageToken.balanceOf(user), 10 ether);
        assertEq(leverageToken.totalSupply(), 10 ether);

        // Redeem 50% of equity
        uint256 sharesToRedeem = sharesToMint / 2;
        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        _redeem(user, sharesToRedeem, previewData.collateral, previewData.debt);

        // 5 ether shares are burned from the user, and 0.45 ether shares are minted to the treasury
        // shares token fee = 5 ether * 0.1 = 0.5 ether
        // treasury fee = (5 ether shares burned from the user - 0.5 ether shares token fee) * 0.1 = 0.45 ether
        // So 5 ether shares are burned from the user, but 0.45 ether shares are minted to the treasury
        // Result is a delta of 4.55 ether
        assertEq(leverageToken.totalSupply(), 5.45 ether);
        assertEq(leverageToken.balanceOf(treasury), 0.45 ether);
        assertEq(leverageToken.balanceOf(user), 5 ether);

        assertEq(WETH.balanceOf(user), previewData.collateral); // User receives the collateral asset

        // One year passes
        skip(SECONDS_ONE_YEAR);

        // Burning the same amount of shares will result in less collateral received due to the share dilution from the
        // management fee and morpho borrow interest
        ActionData memory previewDataAfterYear = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        assertLt(previewDataAfterYear.collateral, previewData.collateral);
    }
}
