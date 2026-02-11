// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageRouter} from "src/interfaces/periphery/ILeverageRouter.sol";
import {IVeloraAdapter} from "src/interfaces/periphery/IVeloraAdapter.sol";
import {LeverageRouterTest} from "./LeverageRouter.t.sol";

contract RedeemWithVeloraTest is LeverageRouterTest {
    function testFuzz_redeemWithVelora_CollateralReceivedWithinSlippage(
        uint128 requiredCollateral,
        uint128 requiredDebt,
        uint128 requiredCollateralForSwap
    ) public {
        vm.assume(requiredDebt < requiredCollateral);

        uint256 mintShares = 10 ether; // Doesn't matter for this test as the deposit and redeem are mocked
        uint256 redeemShares = 5 ether; // Doesn't matter for this test as the deposit and redeem are mocked

        requiredCollateralForSwap = uint128(bound(requiredCollateralForSwap, 0, requiredCollateral));

        veloraAdapter.mockNextBuy(address(collateralToken), requiredCollateralForSwap);
        _mockLeverageManagerRedeem(
            requiredCollateral, requiredDebt, redeemShares, requiredCollateral - requiredCollateralForSwap
        );

        uint256 collateralFromSender = requiredCollateral - requiredDebt;
        _deposit(
            collateralFromSender, // 1:1 exchange rate, 2x leverage
            requiredCollateral,
            requiredDebt,
            requiredCollateral - collateralFromSender,
            mintShares
        );

        // Execute the redeem
        leverageToken.approve(address(leverageRouter), redeemShares);
        leverageRouter.redeemWithVelora(
            leverageToken,
            redeemShares,
            requiredCollateral - requiredCollateralForSwap,
            IVeloraAdapter(address(veloraAdapter)),
            address(0), // Doesn't matter for this test as the swap is mocked
            IVeloraAdapter.Offsets(0, 0, 0), // Doesn't matter for this test as the swap is mocked
            new bytes(0)
        );

        // Senders shares are burned
        assertEq(leverageToken.balanceOf(address(this)), mintShares - redeemShares);

        // The LeverageRouter has the required debt to repay the flash loan and Morpho is approved to spend it
        assertEq(debtToken.balanceOf(address(leverageRouter)), requiredDebt);
        assertEq(debtToken.allowance(address(leverageRouter), address(morpho)), requiredDebt);

        // Sender receives the remaining collateral
        assertEq(collateralToken.balanceOf(address(this)), requiredCollateral - requiredCollateralForSwap);
    }

    function testFuzz_redeemWithVelora_RevertIf_CollateralReceivedOutsideSlippage(
        uint128 requiredCollateral,
        uint128 requiredDebt,
        uint128 requiredCollateralForSwap
    ) public {
        vm.assume(requiredDebt < requiredCollateral);

        uint256 mintShares = 10 ether; // Doesn't matter for this test as the deposit and redeem are mocked
        uint256 redeemShares = 5 ether; // Doesn't matter for this test as the deposit and redeem are mocked

        requiredCollateralForSwap = uint128(bound(requiredCollateralForSwap, 0, requiredCollateral));

        // +1 more than the collateral received to trigger the revert
        uint256 minCollateral = uint256(requiredCollateral) - requiredCollateralForSwap + 1;

        veloraAdapter.mockNextBuy(address(collateralToken), requiredCollateralForSwap);
        _mockLeverageManagerRedeem(requiredCollateral, requiredDebt, redeemShares, minCollateral);

        uint256 collateralFromSender = requiredCollateral - requiredDebt;
        _deposit(
            collateralFromSender, // 1:1 exchange rate, 2x leverage
            requiredCollateral,
            requiredDebt,
            requiredCollateral - collateralFromSender,
            mintShares
        );

        // Execute the redeem
        leverageToken.approve(address(leverageRouter), redeemShares);

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageRouter.CollateralSlippageTooHigh.selector, minCollateral - 1, minCollateral)
        );
        leverageRouter.redeemWithVelora(
            leverageToken,
            redeemShares,
            minCollateral,
            IVeloraAdapter(address(veloraAdapter)),
            address(0), // Doesn't matter for this test as the swap is mocked
            IVeloraAdapter.Offsets(0, 0, 0), // Doesn't matter for this test as the swap is mocked
            new bytes(0)
        );
    }
}
