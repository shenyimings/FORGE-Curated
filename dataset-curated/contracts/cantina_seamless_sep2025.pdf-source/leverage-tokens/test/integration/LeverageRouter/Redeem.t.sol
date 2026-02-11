// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {IUniswapV2Router02} from "src/interfaces/periphery/IUniswapV2Router02.sol";
import {ActionData} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";

contract LeverageRouterRedeemTest is LeverageRouterTest {
    function testFork_redeem_FullRedeem() public {
        uint256 shares = _deposit();

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);
        uint256 collateralForSwap = previewData.collateral * 1.005e18 / 2e18;

        // Approve UniswapV2 to spend the WETH for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(WETH),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, collateralForSwap),
            value: 0
        });
        // Swap WETH to USDC
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                collateralForSwap,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        // On chain exact input swap of collateralForSwap using UniswapV2 results in ~6 USDC being left over
        uint256 expectedSurplusDebt = 6.245106e6;

        _redeemAndAssertBalances(shares, 0, calls, expectedSurplusDebt);
    }

    function testFork_redeem_PartialRedeem() public {
        uint256 shares = _deposit();
        uint256 sharesToRedeem = shares / 2;

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, sharesToRedeem);
        uint256 collateralForSwap = previewData.collateral * 1.005e18 / 2e18;

        // Approve UniswapV2 to spend the WETH for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(WETH),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, collateralForSwap),
            value: 0
        });
        // Swap WETH to USDC
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                collateralForSwap,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        // On chain exact input swap of collateralForSwap using UniswapV2 results in ~3.5 USDC being left over
        uint256 expectedSurplusDebt = 3.538999e6;

        _redeemAndAssertBalances(sharesToRedeem, 0, calls, expectedSurplusDebt);
    }

    function _deposit() internal returns (uint256 shares) {
        uint256 collateralFromSender = 1 ether;
        uint256 userBalanceOfCollateralAsset = 4 ether;
        uint256 flashLoanAmount = 3382.592531e6;

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        ILeverageRouter.Call[] memory calls = new ILeverageRouter.Call[](2);
        // Approve UniswapV2 to spend the USDC for the swap
        calls[0] = ILeverageRouter.Call({
            target: address(USDC),
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V2_ROUTER02, flashLoanAmount),
            value: 0
        });
        // Swap USDC to WETH
        calls[1] = ILeverageRouter.Call({
            target: UNISWAP_V2_ROUTER02,
            data: abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                flashLoanAmount,
                0,
                path,
                address(leverageRouter),
                block.timestamp
            ),
            value: 0
        });

        uint256 sharesBefore = leverageToken.balanceOf(user);

        _dealAndDeposit(WETH, USDC, userBalanceOfCollateralAsset, collateralFromSender, flashLoanAmount, 0, calls);

        uint256 sharesAfter = leverageToken.balanceOf(user) - sharesBefore;

        return sharesAfter;
    }

    function _redeemAndAssertBalances(
        uint256 shares,
        uint256 minCollateralForSender,
        ILeverageRouter.Call[] memory swapCalls,
        uint256 expectedDebtForSender
    ) internal {
        uint256 collateralBeforeRedeem = morphoLendingAdapter.getCollateral();
        uint256 debtBeforeRedeem = morphoLendingAdapter.getDebt();
        uint256 userBalanceOfCollateralAssetBeforeRedeem = WETH.balanceOf(user);

        ActionData memory previewData = leverageManager.previewRedeem(leverageToken, shares);

        vm.startPrank(user);
        leverageToken.approve(address(leverageRouter), shares);
        leverageRouter.redeem(leverageToken, shares, minCollateralForSender, swapCalls);
        vm.stopPrank();

        // Check that the periphery contracts don't hold any assets
        assertEq(WETH.balanceOf(address(leverageRouter)), 0);
        assertEq(USDC.balanceOf(address(leverageRouter)), 0);

        // Collateral and debt are removed from the leverage token
        assertEq(morphoLendingAdapter.getCollateral(), collateralBeforeRedeem - previewData.collateral);
        assertEq(morphoLendingAdapter.getDebt(), debtBeforeRedeem - previewData.debt);

        // The user receives back at least the min collateral
        assertGe(WETH.balanceOf(user), userBalanceOfCollateralAssetBeforeRedeem + minCollateralForSender);

        // Validate that user also received the expected debt surplus from the swap
        assertEq(USDC.balanceOf(user), expectedDebtForSender);
    }
}
