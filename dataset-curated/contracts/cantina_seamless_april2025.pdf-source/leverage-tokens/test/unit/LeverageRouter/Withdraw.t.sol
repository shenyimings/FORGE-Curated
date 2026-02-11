// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";
import {ExternalAction} from "src/types/DataTypes.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";
import {MockLeverageManager} from "../mock/MockLeverageManager.sol";

contract WithdrawTest is LeverageRouterTest {
    function testFuzz_withdraw_CollateralSwapWithinMaxCostForFlashLoanRepaymentDebt(
        uint128 requiredCollateral,
        uint128 requiredDebt,
        uint128 equityInCollateralAsset,
        uint256 requiredCollateralForSwap,
        uint128 maxSwapCostInCollateralAsset
    ) public {
        vm.assume(requiredDebt < requiredCollateral);

        uint256 depositShares = 10 ether; // Doesn't matter for this test as the shares received and previewed are mocked
        uint256 withdrawShares = 5 ether; // Doesn't matter for this test as the shares received and previewed are mocked

        equityInCollateralAsset = requiredCollateral - requiredDebt;
        maxSwapCostInCollateralAsset = uint128(bound(maxSwapCostInCollateralAsset, 0, equityInCollateralAsset - 1));

        // Bound the required collateral for the swap to repay the debt flash loan to be within the max swap cost
        requiredCollateralForSwap = uint256(
            bound(
                requiredCollateralForSwap,
                0,
                uint256(requiredCollateral) - equityInCollateralAsset + maxSwapCostInCollateralAsset
            )
        );

        _mockLeverageManagerWithdraw(
            requiredCollateral, equityInCollateralAsset, requiredDebt, requiredCollateralForSwap, withdrawShares
        );

        _deposit(
            equityInCollateralAsset,
            requiredCollateral,
            requiredDebt,
            requiredCollateral - equityInCollateralAsset,
            depositShares
        );

        // Execute the withdraw
        deal(address(debtToken), address(this), requiredDebt);
        debtToken.approve(address(leverageRouter), requiredDebt);
        leverageToken.approve(address(leverageRouter), withdrawShares);
        leverageRouter.withdraw(
            leverageToken,
            equityInCollateralAsset,
            withdrawShares,
            maxSwapCostInCollateralAsset,
            // Mock the swap context (doesn't matter for this test as the swap is mocked)
            ISwapAdapter.SwapContext({
                path: new address[](0),
                encodedPath: new bytes(0),
                fees: new uint24[](0),
                tickSpacing: new int24[](0),
                exchange: ISwapAdapter.Exchange.AERODROME,
                exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                    aerodromeRouter: address(0),
                    aerodromePoolFactory: address(0),
                    aerodromeSlipstreamRouter: address(0),
                    uniswapSwapRouter02: address(0),
                    uniswapV2Router02: address(0)
                })
            })
        );

        // Senders shares are burned
        assertEq(leverageToken.balanceOf(address(this)), depositShares - withdrawShares);

        // The LeverageRouter has the required debt to repay the flash loan and Morpho is approved to spend it
        assertEq(debtToken.balanceOf(address(leverageRouter)), requiredDebt);
        assertEq(debtToken.allowance(address(leverageRouter), address(morpho)), requiredDebt);

        // Sender receives the remaining collateral (equity)
        assertEq(collateralToken.balanceOf(address(this)), requiredCollateral - requiredCollateralForSwap);
        assertGe(collateralToken.balanceOf(address(this)), equityInCollateralAsset - maxSwapCostInCollateralAsset);
    }

    function testFuzz_withdraw_CollateralSwapMoreThanMaxCostForFlashLoanRepaymentDebt(
        uint128 requiredCollateral,
        uint128 requiredDebt,
        uint128 equityInCollateralAsset,
        uint256 requiredCollateralForSwap,
        uint128 maxSwapCostInCollateralAsset
    ) public {
        vm.assume(requiredDebt < requiredCollateral);

        uint256 shares = 10 ether; // Doesn't matter for this test as the shares received and previewed are mocked

        equityInCollateralAsset = requiredCollateral - requiredDebt;
        maxSwapCostInCollateralAsset = uint128(bound(maxSwapCostInCollateralAsset, 0, equityInCollateralAsset - 1));

        // Bound the required collateral for the swap to repay the debt flash loan to dip deeper into the equity than
        // allowed, per the max swap cost parameter
        requiredCollateralForSwap = uint256(
            bound(
                requiredCollateralForSwap,
                uint256(requiredCollateral) - equityInCollateralAsset + maxSwapCostInCollateralAsset + 1,
                requiredCollateral
            )
        );

        _mockLeverageManagerWithdraw(
            requiredCollateral, equityInCollateralAsset, requiredDebt, requiredCollateralForSwap, shares
        );

        _deposit(
            equityInCollateralAsset,
            requiredCollateral,
            requiredDebt,
            requiredCollateral - equityInCollateralAsset,
            shares
        );

        // Execute the withdraw
        deal(address(debtToken), address(this), requiredDebt);
        debtToken.approve(address(leverageRouter), requiredDebt);
        leverageToken.approve(address(leverageRouter), shares);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILeverageRouter.MaxSwapCostExceeded.selector,
                equityInCollateralAsset - (requiredCollateral - requiredCollateralForSwap),
                maxSwapCostInCollateralAsset
            )
        );
        leverageRouter.withdraw(
            leverageToken,
            equityInCollateralAsset,
            shares,
            maxSwapCostInCollateralAsset,
            // Mock the swap context (doesn't matter for this test as the swap is mocked)
            ISwapAdapter.SwapContext({
                path: new address[](0),
                encodedPath: new bytes(0),
                fees: new uint24[](0),
                tickSpacing: new int24[](0),
                exchange: ISwapAdapter.Exchange.AERODROME,
                exchangeAddresses: ISwapAdapter.ExchangeAddresses({
                    aerodromeRouter: address(0),
                    aerodromePoolFactory: address(0),
                    aerodromeSlipstreamRouter: address(0),
                    uniswapSwapRouter02: address(0),
                    uniswapV2Router02: address(0)
                })
            })
        );
    }
}
