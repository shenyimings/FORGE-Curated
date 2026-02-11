// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";
import {MockLeverageManager} from "../mock/MockLeverageManager.sol";
import {MockSwapper} from "../mock/MockSwapper.sol";

contract DepositTest is LeverageRouterTest {
    function testFuzz_Deposit_DebtSwapResultGteRequiredCollateralForDeposit(
        uint256 requiredCollateral,
        uint256 debtFlashLoan,
        uint256 debtFromDeposit,
        uint256 collateralFromSender,
        uint256 collateralReceivedFromDebtSwap
    ) public {
        requiredCollateral = bound(requiredCollateral, 1, type(uint256).max);
        // Ensure that a flash loan is required by making collateralFromSender less than the required collateral for the deposit
        collateralFromSender = requiredCollateral > 1 ? bound(collateralFromSender, 1, requiredCollateral - 1) : 0;

        // Bound the debt from the deposit to be >= the debt flash loan
        debtFromDeposit = bound(debtFromDeposit, debtFlashLoan, type(uint256).max);

        uint256 requiredCollateralFromSwap = requiredCollateral - collateralFromSender;

        // Mock collateral received from the debt swap to be >= the required amount
        collateralReceivedFromDebtSwap =
            bound(collateralReceivedFromDebtSwap, requiredCollateralFromSwap, type(uint256).max - collateralFromSender);

        // Mocked exchange rate of shares (Doesn't matter for this test as the shares received and previewed are mocked)
        uint256 shares = 10 ether;

        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
        _mockLeverageManagerDeposit(totalCollateral, debtFromDeposit, collateralReceivedFromDebtSwap, shares);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(debtToken),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swapper), debtFlashLoan),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: address(swapper),
            data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, debtToken, debtFlashLoan),
            value: 0
        });

        // Execute the deposit
        deal(address(collateralToken), address(this), collateralFromSender);
        collateralToken.approve(address(leverageRouter), collateralFromSender);
        leverageRouter.deposit(leverageToken, collateralFromSender, debtFlashLoan, shares, calls);

        // Sender receives the minted shares
        assertEq(leverageToken.balanceOf(address(this)), shares);
        assertEq(leverageToken.balanceOf(address(leverageRouter)), 0);

        // The LeverageRouter has the required collateral to repay the flash loan and Morpho is approved to spend it
        assertEq(debtToken.balanceOf(address(leverageRouter)), debtFlashLoan);
        assertEq(debtToken.allowance(address(leverageRouter), address(morpho)), debtFlashLoan);

        // Sender receives any surplus debt asset not used to repay the flash loan
        assertEq(debtToken.balanceOf(address(this)), debtFromDeposit - debtFlashLoan);

        // LeverageRouter has no leftover collateral
        assertEq(collateralToken.balanceOf(address(leverageRouter)), 0);
    }

    function testFuzz_Deposit_DebtSwapLessThanRequiredCollateralForDeposit(
        uint256 requiredCollateral,
        uint256 debtFlashLoan,
        uint256 debtFromDeposit,
        uint256 collateralFromSender,
        uint256 collateralReceivedFromDebtSwap
    ) public {
        requiredCollateral = bound(requiredCollateral, 1, type(uint256).max);
        // Ensure that a flash loan is required by making collateralFromSender less than the required collateral for the deposit
        collateralFromSender = requiredCollateral > 1 ? bound(collateralFromSender, 1, requiredCollateral - 1) : 0;

        debtFlashLoan = bound(debtFlashLoan, 1, type(uint256).max);
        // Bound the debt from the deposit to be < the debt flash loan
        debtFromDeposit = bound(debtFromDeposit, 0, debtFlashLoan - 1);

        uint256 requiredCollateralFromSwap = requiredCollateral - collateralFromSender;

        // Mock collateral received from the debt swap to be < the required amount
        collateralReceivedFromDebtSwap = bound(collateralReceivedFromDebtSwap, 0, requiredCollateralFromSwap - 1);

        // Mocked exchange rate of shares (Doesn't matter for this test as the shares received and previewed are mocked)
        uint256 shares = 10 ether;

        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;
        _mockLeverageManagerDeposit(totalCollateral, debtFromDeposit, collateralReceivedFromDebtSwap, shares);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(debtToken),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swapper), debtFlashLoan),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: address(swapper),
            data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, debtToken, debtFlashLoan),
            value: 0
        });

        // Execute the deposit
        deal(address(collateralToken), address(this), collateralFromSender);
        collateralToken.approve(address(leverageRouter), collateralFromSender);
        leverageRouter.deposit(leverageToken, collateralFromSender, debtFlashLoan, shares, calls);

        // Sender receives the minted shares
        assertEq(leverageToken.balanceOf(address(this)), shares);
        assertEq(leverageToken.balanceOf(address(leverageRouter)), 0);

        // The LeverageRouter does not have the required collateral to repay the flash loan
        assertLt(debtToken.balanceOf(address(leverageRouter)), debtFlashLoan);

        // Morpho is approved to spend the debt flash loan, even if the LR holds less debt than the flash loan
        // In reality, the whole transaction will revert when morpho attempts to spend the LR's debt to repay the flash
        // loan, so this allowance would not take effect afterwards
        assertEq(debtToken.allowance(address(leverageRouter), address(morpho)), debtFlashLoan);

        // Sender receives no debt as there is no surplus
        assertEq(debtToken.balanceOf(address(this)), 0);

        // LeverageRouter has no leftover collateral
        assertEq(collateralToken.balanceOf(address(leverageRouter)), 0);
    }

    function testFuzz_Deposit_RevertIf_InsufficientDebtFromDepositToRepayFlashLoan(
        uint256 requiredCollateral,
        uint256 debtFlashLoan,
        uint256 debtFromDeposit,
        uint256 collateralFromSender,
        uint256 collateralReceivedFromDebtSwap
    ) public {
        requiredCollateral = bound(requiredCollateral, 1, type(uint256).max);
        // Ensure that a flash loan is required by making collateralFromSender less than the required collateral for the deposit
        collateralFromSender = requiredCollateral > 1 ? bound(collateralFromSender, 1, requiredCollateral - 1) : 0;

        debtFlashLoan = bound(debtFlashLoan, 1, type(uint256).max);
        // Bound the debt from the deposit to be < the debt flash loan
        debtFromDeposit = bound(debtFromDeposit, 0, debtFlashLoan - 1);

        uint256 requiredCollateralFromSwap = requiredCollateral - collateralFromSender;

        // Mock collateral received from the debt swap to be < the required amount
        collateralReceivedFromDebtSwap = bound(collateralReceivedFromDebtSwap, 0, requiredCollateralFromSwap - 1);

        // Mocked exchange rate of shares (Doesn't matter for this test as the shares received and previewed are mocked)
        uint256 shares = 10 ether;

        // Total collateral available for the deosit
        uint256 totalCollateral = collateralFromSender + collateralReceivedFromDebtSwap;

        // Mock the swap of the debt asset to the collateral asset
        swapper.mockNextExactInputSwap(debtToken, collateralToken, collateralReceivedFromDebtSwap);

        // Execute the deposit
        deal(address(collateralToken), address(this), collateralFromSender);
        collateralToken.approve(address(leverageRouter), collateralFromSender);

        _mockLeverageManagerDeposit(totalCollateral, debtFromDeposit, collateralReceivedFromDebtSwap, shares);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(debtToken),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swapper), debtFlashLoan),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: address(swapper),
            data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, debtToken, debtFlashLoan),
            value: 0
        });

        leverageRouter.deposit(leverageToken, collateralFromSender, debtFlashLoan, shares, calls);

        // Mimic Morpho attempting to transfer debt from the LeverageRouter to repay the flash loan
        vm.startPrank(address(morpho));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(leverageRouter),
                debtToken.balanceOf(address(leverageRouter)),
                debtFlashLoan
            )
        );
        debtToken.transferFrom(address(leverageRouter), address(morpho), debtFlashLoan);
        vm.stopPrank();
    }
}
