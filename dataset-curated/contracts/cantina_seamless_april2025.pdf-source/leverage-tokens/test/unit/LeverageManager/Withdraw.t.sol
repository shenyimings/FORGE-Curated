// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ActionData, ExternalAction} from "src/types/DataTypes.sol";
import {PreviewActionTest} from "./PreviewAction.t.sol";

contract WithdrawTest is PreviewActionTest {
    function test_withdraw_WithFees() public {
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Withdraw, 0.05e4); // 5% fee
        _setTreasuryActionFee(ExternalAction.Withdraw, 0.05e4); // 5% fee

        // 1:2 exchange rate
        lendingAdapter.mockConvertCollateralToDebtAssetExchangeRate(2e8);

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 equityToWithdraw = 10 ether;
        _testWithdraw(equityToWithdraw, type(uint256).max);
    }

    function test_withdraw_WithoutFees() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 equityToWithdraw = 10 ether;
        _testWithdraw(equityToWithdraw, type(uint256).max);
    }

    function test_withdraw_TreasuryNotSet() public {
        _setTreasury(feeManagerRole, address(0));

        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        uint256 equityToWithdraw = 10 ether;
        _testWithdraw(equityToWithdraw, type(uint256).max);

        assertEq(collateralToken.balanceOf(address(treasury)), 0);
    }

    function test_withdraw_ZeroEquity() public {
        MockLeverageManagerStateForAction memory beforeState =
            MockLeverageManagerStateForAction({collateral: 200 ether, debt: 100 ether, sharesTotalSupply: 100 ether});

        _prepareLeverageManagerStateForAction(beforeState);

        _testWithdraw(0, type(uint256).max);
    }

    function testFuzz_withdraw_RevertIf_SlippageTooHigh(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 sharesTotalSupply,
        uint128 equityToWithdrawInCollateralAsset,
        uint16 tokenFee,
        uint16 treasuryFee
    ) public {
        tokenFee = uint16(bound(tokenFee, 0, 1e4));
        treasuryFee = uint16(bound(treasuryFee, 0, 1e4));
        initialDebtInCollateralAsset = uint128(bound(initialDebtInCollateralAsset, 0, initialCollateral));
        sharesTotalSupply = uint128(bound(sharesTotalSupply, 1, type(uint128).max));

        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Withdraw, tokenFee);
        _setTreasuryActionFee(ExternalAction.Withdraw, treasuryFee);

        vm.assume(initialCollateral > initialDebtInCollateralAsset);
        vm.assume(equityToWithdrawInCollateralAsset > 0);

        // Preview the withdrawal
        uint256 expectedShares =
            leverageManager.previewWithdraw(leverageToken, equityToWithdrawInCollateralAsset).shares;

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.SlippageTooHigh.selector, expectedShares, expectedShares - 1)
        );
        leverageManager.withdraw(leverageToken, equityToWithdrawInCollateralAsset, expectedShares - 1);
    }

    function testFuzz_withdraw(
        uint128 initialCollateral,
        uint128 initialDebtInCollateralAsset,
        uint128 sharesTotalSupply,
        uint128 equityToWithdrawInCollateralAsset,
        uint16 tokenFee,
        uint16 treasuryFee
    ) public {
        tokenFee = uint16(bound(tokenFee, 0, 1e4));
        treasuryFee = uint16(bound(treasuryFee, 0, 1e4));
        leverageManager.exposed_setLeverageTokenActionFee(leverageToken, ExternalAction.Withdraw, tokenFee);
        _setTreasuryActionFee(ExternalAction.Withdraw, treasuryFee);

        // Bound debt to be lower than collateral asset and share total supply to be greater than 0 otherwise withdraw can not work
        initialDebtInCollateralAsset = uint128(bound(initialDebtInCollateralAsset, 0, initialCollateral));
        sharesTotalSupply = uint128(bound(sharesTotalSupply, 1, type(uint128).max));

        _prepareLeverageManagerStateForAction(
            MockLeverageManagerStateForAction({
                collateral: initialCollateral,
                debt: initialDebtInCollateralAsset,
                sharesTotalSupply: sharesTotalSupply
            })
        );

        // Ensure withdrawal amount doesn't exceed available equity
        equityToWithdrawInCollateralAsset =
            uint128(bound(equityToWithdrawInCollateralAsset, 0, initialCollateral - initialDebtInCollateralAsset));

        _testWithdraw(equityToWithdrawInCollateralAsset, type(uint256).max);
    }

    function _testWithdraw(uint256 equityToWithdrawInCollateralAsset, uint256 maxShares) internal {
        // First preview the withdrawal
        ActionData memory previewData =
            leverageManager.previewWithdraw(leverageToken, equityToWithdrawInCollateralAsset);

        uint256 shareTotalSupplyBefore = leverageToken.totalSupply();

        vm.assume(previewData.shares <= shareTotalSupplyBefore);

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

        // Execute withdrawal
        ActionData memory withdrawData =
            leverageManager.withdraw(leverageToken, equityToWithdrawInCollateralAsset, maxShares);

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
        assertEq(leverageToken.totalSupply(), shareTotalSupplyBefore - withdrawData.shares);
        assertEq(leverageToken.balanceOf(address(this)), 0);

        // Verify that the treasury received the fee
        assertEq(collateralToken.balanceOf(treasury), withdrawData.treasuryFee);

        // Verify that if any collateral is returned, the amount of shares burned must be non-zero
        if (withdrawData.collateral > 0) {
            assertGt(withdrawData.shares, 0);
            assertLt(leverageToken.totalSupply(), shareTotalSupplyBefore);
        }

        // Fees should be less than or equal to the equity to withdraw
        assertLe(withdrawData.tokenFee + withdrawData.treasuryFee, equityToWithdrawInCollateralAsset);
    }
}
