// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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

contract LeverageManagerWithdrawTest is LeverageManagerTest {
    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_withdraw_NoFee() public {
        uint256 sharesToMint = 10 ether;
        uint256 collateral = leverageManager.previewMint(leverageToken, sharesToMint).collateral;
        _mint(user, sharesToMint, collateral);

        LeverageTokenState memory stateBefore = getLeverageTokenState();
        uint256 collateralBefore = morphoLendingAdapter.getCollateral();

        uint256 collateralToWithdraw = collateral / 2;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        _withdraw(user, collateralToWithdraw, previewData.shares, previewData.debt);

        LeverageTokenState memory stateAfter = getLeverageTokenState();

        // Ensure that collateral ratio is the same (with some rounding error)
        // Verify the collateral ratio is >= the collateral ratio before the withdraw
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(morphoLendingAdapter.getCollateral() * stateBefore.debt, collateralBefore * stateAfter.debt);

        assertEq(stateAfter.debt, stateBefore.debt - previewData.debt);
        assertEq(WETH.balanceOf(user), previewData.collateral);
    }

    function testFork_withdraw_ZeroAmount() public {
        uint256 sharesToMint = 10 ether;
        uint256 collateral = leverageManager.previewMint(leverageToken, sharesToMint).collateral;
        _mint(user, sharesToMint, collateral);

        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, 0);
        _withdraw(user, 0, previewData.shares, previewData.debt);

        assertEq(previewData.collateral, 0);
        assertEq(previewData.debt, 0);
        assertEq(previewData.shares, 0);
    }

    function testFork_withdraw_FullWithdraw() public {
        (,, address oracle,,) = morphoLendingAdapter.marketParams();
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(4000e24));

        uint256 shares = 10 ether;
        uint256 collateral = leverageManager.previewMint(leverageToken, shares).collateral;
        _mint(user, shares, collateral);

        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateral);
        _withdraw(user, collateral, previewData.shares, previewData.debt);

        // Validate that all shares are burned
        assertEq(leverageToken.totalSupply(), 0);

        // Validate that all collateral is withdrawn
        assertEq(morphoLendingAdapter.getCollateral(), 0);

        // Validate that entire debt is repaid successfully
        assertEq(morphoLendingAdapter.getDebt(), 0);
    }

    function testFork_withdraw_MockPrice() public {
        // Mock ETH price to be 4000 USDC
        (,, address oracle,,) = morphoLendingAdapter.marketParams();
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(4000e24));

        uint256 sharesToMint = 10 ether;
        uint256 collateral = leverageManager.previewMint(leverageToken, sharesToMint).collateral;
        _mint(user, sharesToMint, collateral);

        LeverageTokenState memory stateBefore = getLeverageTokenState();
        uint256 collateralBefore = morphoLendingAdapter.getCollateral();
        assertEq(stateBefore.collateralRatio, 1999999999950000000); // ~2x CR

        uint256 collateralBeforeWithdraw = morphoLendingAdapter.getCollateral();

        uint256 collateralToWithdraw = collateral / 2;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        _withdraw(user, collateralToWithdraw, previewData.shares, previewData.debt);

        LeverageTokenState memory stateAfter = getLeverageTokenState();
        uint256 collateralAfterWithdraw = morphoLendingAdapter.getCollateral();

        // Ensure that collateral ratio is the same (with some rounding error)
        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);
        // Verify the collateral ratio is >= the collateral ratio before the withdraw
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(morphoLendingAdapter.getCollateral() * stateBefore.debt, collateralBefore * stateAfter.debt);
        assertEq(stateAfter.collateralRatio, 2000000000000000000);

        // Ensure that after redeem debt and collateral is 50% of what was initially after mint
        assertEq(stateAfter.debt, 20000e6); // 20000 USDC
        assertEq(collateralAfterWithdraw, collateralBeforeWithdraw / 2);

        assertEq(WETH.balanceOf(user), previewData.collateral);
    }

    function testFork_withdraw_PriceChangedBetweenRedeems_CollateralRatioDoesNotChange() public {
        uint256 sharesToMint = 10 ether;
        uint256 collateral = leverageManager.previewMint(leverageToken, sharesToMint).collateral;
        _mint(user, sharesToMint, collateral);

        // Mock ETH price to be 4000 USDC
        (,, address oracle,,) = morphoLendingAdapter.marketParams();
        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(4000e24));

        LeverageTokenState memory stateBefore = getLeverageTokenState();
        uint256 collateralBefore = morphoLendingAdapter.getCollateral();
        assertEq(stateBefore.collateralRatio, 2358287225224640032); // ~2x CR

        uint256 collateralToWithdraw = collateral / 2;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        _withdraw(user, collateralToWithdraw, previewData.shares, previewData.debt);

        LeverageTokenState memory stateAfter = getLeverageTokenState();

        // Ensure that collateral ratio is the same (with some rounding error)
        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);
        // Verify the collateral ratio is >= the collateral ratio before the withdraw
        // We use the comparison collateralBefore * debtAfter >= collateralAfter * debtBefore, which is equivalent to
        // collateralRatioAfter >= collateralRatioBefore to avoid precision loss from division when calculating collateral
        // ratios
        assertGe(morphoLendingAdapter.getCollateral() * stateBefore.debt, collateralBefore * stateAfter.debt);
        assertEq(stateAfter.collateralRatio, 2358287225224640032);

        assertEq(WETH.balanceOf(user), previewData.collateral);
    }

    function testFork_withdraw_FullWithdrawComparedToPartialWithdraw() public {
        // Mint some assets initially
        uint256 sharesToMint = 10 ether;
        uint256 collateral = leverageManager.previewMint(leverageToken, sharesToMint).collateral;
        _mint(user, sharesToMint, collateral);

        // Withdraw everything
        ActionData memory previewDataAfterMint = leverageManager.previewWithdraw(leverageToken, collateral);
        _withdraw(user, collateral, previewDataAfterMint.shares, previewDataAfterMint.debt);

        // Mint again to create the same scenario
        _mint(user, sharesToMint, collateral);

        // Withdraw half of it
        uint256 collateralToWithdraw = collateral / 2;
        ActionData memory previewDataFirstTime = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        _withdraw(user, collateralToWithdraw, previewDataFirstTime.shares, previewDataFirstTime.debt);

        // Withdraw the rest
        ActionData memory previewDataSecondTime = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        _withdraw(user, collateralToWithdraw, previewDataSecondTime.shares, previewDataSecondTime.debt);

        // Validate that in both cases we get the same amount of collateral and debt
        assertEq(previewDataFirstTime.collateral + previewDataSecondTime.collateral, previewDataAfterMint.collateral);
        assertEq(previewDataFirstTime.debt + previewDataSecondTime.debt, previewDataAfterMint.debt);

        // Validate that collateral token is properly transferred to user
        assertEq(WETH.balanceOf(user), previewDataFirstTime.collateral + previewDataSecondTime.collateral);
        assertLe(previewDataAfterMint.collateral, 2 * sharesToMint);
    }

    function testFork_withdraw_withFee() public {
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
        uint256 collateral = leverageManager.previewMint(leverageToken, sharesToMint).collateral;
        _mint(user, sharesToMint, collateral);

        // 10% of equity goes to share dilution (token action fee), so 9 ether shares are minted instead of 10 ether
        assertEq(leverageToken.balanceOf(user), 10 ether);
        assertEq(leverageToken.totalSupply(), 10 ether);

        // Withdraw 50% of collateral
        uint256 collateralToWithdraw = collateral / 2;
        ActionData memory previewData = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        _withdraw(user, collateralToWithdraw, previewData.shares, previewData.debt);

        assertEq(leverageToken.totalSupply(), sharesToMint - previewData.shares + previewData.treasuryFee);

        assertEq(WETH.balanceOf(user), collateralToWithdraw); // User receives the collateral asset

        // One year passes
        skip(SECONDS_ONE_YEAR);

        // Withdrawing the other half of collateral is not possible for the user due to share dilution from the management fee
        // and morpho borrow interest
        ActionData memory previewDataAfterYear = leverageManager.previewWithdraw(leverageToken, collateralToWithdraw);
        assertEq(previewDataAfterYear.shares, 5.951836610272824265 ether);
        assertGt(previewDataAfterYear.shares, leverageToken.balanceOf(user));

        deal(address(USDC), user, previewDataAfterYear.debt);
        vm.startPrank(user);
        USDC.approve(address(leverageManager), previewDataAfterYear.debt);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(user),
                leverageToken.balanceOf(user),
                previewDataAfterYear.shares
            )
        );
        leverageManager.withdraw(leverageToken, collateralToWithdraw, previewDataAfterYear.shares);
        vm.stopPrank();
    }
}
