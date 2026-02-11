// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {IVeloraAdapter} from "src/interfaces/periphery/IVeloraAdapter.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";
import {MockSwapper} from "../mock/MockSwapper.sol";

contract OnMorphoFlashLoanTest is LeverageRouterTest {
    function test_onMorphoFlashLoan_Deposit() public {
        uint256 requiredCollateral = 10 ether;
        uint256 collateralFromSender = 5 ether;
        uint256 collateralReceivedFromDebtSwap = 5 ether;
        uint256 shares = 10 ether;
        uint256 requiredDebt = 100e6;

        _mockLeverageManagerDeposit(requiredCollateral, requiredDebt, collateralReceivedFromDebtSwap, shares);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(debtToken),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swapper), requiredDebt),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: address(swapper),
            data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, debtToken, requiredDebt),
            value: 0
        });

        bytes memory depositData = abi.encode(
            ILeverageRouter.DepositParams({
                leverageToken: leverageToken,
                collateralFromSender: collateralFromSender,
                minShares: shares,
                sender: address(this),
                swapCalls: calls
            })
        );

        deal(address(collateralToken), address(this), collateralFromSender);
        collateralToken.approve(address(leverageRouter), collateralFromSender);

        // Also mock morpho flash loaning the debt required for the deposit
        uint256 flashLoanAmount = requiredDebt;
        deal(address(debtToken), address(leverageRouter), flashLoanAmount);

        vm.prank(address(morpho));
        leverageRouter.onMorphoFlashLoan(
            flashLoanAmount,
            abi.encode(
                ILeverageRouter.MorphoCallbackData({
                    action: ILeverageRouter.LeverageRouterAction.Deposit,
                    data: depositData
                })
            )
        );
        assertEq(leverageToken.balanceOf(address(this)), shares);
        assertEq(debtToken.balanceOf(address(leverageRouter)), requiredDebt);
        assertEq(debtToken.allowance(address(leverageRouter), address(morpho)), requiredDebt);
    }

    function test_onMorphoFlashLoan_Redeem() public {
        uint256 requiredCollateral = 10 ether;
        uint256 collateralFromSender = 5 ether;
        uint256 collateralReceivedFromDebtSwap = 5 ether;
        uint256 shares = 10 ether;
        uint256 requiredDebt = 100e6;
        uint256 excessDebt = 10e6;

        _deposit(collateralFromSender, requiredCollateral, requiredDebt, collateralReceivedFromDebtSwap, shares);

        uint256 requiredCollateralForSwap = requiredCollateral - collateralFromSender;
        swapper.mockNextExactInputSwap(collateralToken, debtToken, uint256(requiredDebt) + excessDebt);
        _mockLeverageManagerRedeem(
            requiredCollateral, requiredDebt, shares, requiredCollateral - requiredCollateralForSwap
        );

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        calls[0] = ILeverageRouter.Call({
            target: address(collateralToken),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(swapper), requiredCollateralForSwap),
            value: 0
        });
        calls[1] = ILeverageRouter.Call({
            target: address(swapper),
            data: abi.encodeWithSelector(MockSwapper.swapExactInput.selector, collateralToken, requiredCollateralForSwap),
            value: 0
        });

        bytes memory redeemData = abi.encode(
            ILeverageRouter.RedeemParams({
                leverageToken: leverageToken,
                shares: shares,
                minCollateralForSender: requiredCollateral - requiredCollateralForSwap,
                sender: address(this),
                swapCalls: calls
            })
        );

        leverageToken.approve(address(leverageRouter), shares);

        // Mock morpho flash loaning the debt required for the redeem
        uint256 flashLoanAmount = requiredDebt;
        deal(address(debtToken), address(leverageRouter), flashLoanAmount);

        vm.prank(address(morpho));
        leverageRouter.onMorphoFlashLoan(
            flashLoanAmount,
            abi.encode(
                ILeverageRouter.MorphoCallbackData({
                    action: ILeverageRouter.LeverageRouterAction.Redeem,
                    data: redeemData
                })
            )
        );
        assertEq(leverageToken.balanceOf(address(this)), 0);
        assertEq(collateralToken.balanceOf(address(this)), requiredCollateral - requiredCollateralForSwap);
        assertEq(debtToken.balanceOf(address(this)), excessDebt);
    }

    function test_onMorphoFlashLoan_RedeemWithVelora() public {
        uint256 requiredCollateral = 10 ether;
        uint256 collateralFromSender = 5 ether;
        uint256 collateralReceivedFromDebtSwap = 5 ether;
        uint256 shares = 10 ether;
        uint256 requiredDebt = 100e6;

        _deposit(collateralFromSender, requiredCollateral, requiredDebt, collateralReceivedFromDebtSwap, shares);

        uint256 requiredCollateralForSwap = requiredCollateral - collateralFromSender;
        veloraAdapter.mockNextBuy(address(collateralToken), requiredCollateralForSwap);
        _mockLeverageManagerRedeem(
            requiredCollateral, requiredDebt, shares, requiredCollateral - requiredCollateralForSwap
        );

        bytes memory redeemWithVeloraData = abi.encode(
            ILeverageRouter.RedeemWithVeloraParams({
                leverageToken: leverageToken,
                shares: shares,
                minCollateralForSender: requiredCollateral - requiredCollateralForSwap,
                sender: address(this),
                veloraAdapter: IVeloraAdapter(address(veloraAdapter)),
                augustus: address(0),
                offsets: IVeloraAdapter.Offsets(0, 0, 0),
                swapData: new bytes(0)
            })
        );

        leverageToken.approve(address(leverageRouter), shares);

        // Mock morpho flash loaning the debt required for the redeem
        uint256 flashLoanAmount = requiredDebt;
        deal(address(debtToken), address(leverageRouter), flashLoanAmount);

        vm.prank(address(morpho));
        leverageRouter.onMorphoFlashLoan(
            flashLoanAmount,
            abi.encode(
                ILeverageRouter.MorphoCallbackData({
                    action: ILeverageRouter.LeverageRouterAction.RedeemWithVelora,
                    data: redeemWithVeloraData
                })
            )
        );
        assertEq(leverageToken.balanceOf(address(this)), 0);
        assertEq(collateralToken.balanceOf(address(this)), requiredCollateral - requiredCollateralForSwap);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_onMorphoFlashLoan_RevertIf_Unauthorized(address caller) public {
        vm.assume(caller != address(morpho));
        vm.expectRevert(ILeverageRouter.Unauthorized.selector);
        leverageRouter.onMorphoFlashLoan(0, "");
    }
}
