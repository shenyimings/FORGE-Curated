// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {RebalanceTest, RebalanceType} from "test/integration/LeverageManager/Rebalance.t.sol";
import {RebalanceAction, LeverageTokenState} from "src/types/DataTypes.sol";

contract PreLiquidationRebalanceTest is RebalanceTest {
    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_RebalanceStrategyOutsideOfDutchAuctionIfCloseToLiquidation() public {
        _mintEthLong2x();

        _moveEthPrice(-40_00);

        // ETH price is now 2035$
        LeverageTokenState memory stateBefore = getLeverageTokenState(ethLong2x);

        // On this market liquidation penalty is 4.38% which means that our rebalance reward is 45.66% of it which is 2%
        // This means that user can take 2% of debt repaid from equity
        // 2.5 ETH is worth 5,087.5 USDC
        // User is repaying 5,000 USDC debt which means that he can profit 100 USDC max
        // By taking 2.5 ETH he is profiting around 87.5 USDC which should be fine

        uint256 collateralToRemove = 2.5e18;
        uint256 debtToRepay = 5_000e6;

        (RebalanceAction[] memory actions, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOut) =
            _prepareForRebalance(ethLong2x, RebalanceType.DOWN, 0, collateralToRemove, 0, debtToRepay); // Give 5000 USDC and take 2.5 ETH

        deal(address(USDC), address(this), debtToRepay);
        USDC.approve(address(leverageManager), debtToRepay);
        leverageManager.rebalance(ethLong2x, actions, tokenIn, tokenOut, amountIn, amountOut);

        LeverageTokenState memory stateAfter = getLeverageTokenState(ethLong2x);
        assertLe(stateAfter.equity, stateBefore.equity);
        assertGe(stateAfter.equity, stateBefore.equity - 100e6);

        assertEq(WETH.balanceOf(address(this)), collateralToRemove);
        assertEq(USDC.balanceOf(address(this)), 0);

        assertGe(stateAfter.collateralRatio, stateBefore.collateralRatio);
    }

    function testFork_RebalanceStrategyOutsideOfDutchAuctionIfCloseToLiquidation_RevertIfEquityLossIsTooHigh() public {
        _mintEthLong2x();

        _moveEthPrice(-40_00);

        uint256 colToRemove = 2.6e18;
        uint256 debtToRepay = 5_000e6;

        (RebalanceAction[] memory actions, IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOut) =
            _prepareForRebalance(ethLong2x, RebalanceType.DOWN, 0, colToRemove, 0, debtToRepay); // Give 5000 USDC and take 2.6 ETH

        deal(address(USDC), address(this), debtToRepay);
        USDC.approve(address(leverageManager), debtToRepay);

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.InvalidLeverageTokenStateAfterRebalance.selector, ethLong2x)
        );
        leverageManager.rebalance(ethLong2x, actions, tokenIn, tokenOut, amountIn, amountOut);
    }
}
