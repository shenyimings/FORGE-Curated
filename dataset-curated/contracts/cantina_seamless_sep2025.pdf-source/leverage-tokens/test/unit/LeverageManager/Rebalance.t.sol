// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {LeverageManagerTest} from "test/unit/LeverageManager/LeverageManager.t.sol";
import {MockLendingAdapter} from "test/unit/mock/MockLendingAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {MockRebalanceAdapter} from "test/unit/mock/MockRebalanceAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {RebalanceAction, ActionType, LeverageTokenConfig, LeverageTokenState} from "src/types/DataTypes.sol";

contract RebalanceTest is LeverageManagerTest {
    ERC20Mock public WETH = new ERC20Mock();
    ERC20Mock public USDC = new ERC20Mock();

    MockLendingAdapter public adapter;

    function setUp() public override {
        super.setUp();

        adapter = new MockLendingAdapter(address(WETH), address(USDC), manager);

        _createNewLeverageToken(
            manager,
            2e18,
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(adapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: 0
            }),
            address(WETH),
            address(USDC),
            "ETH Long 2x",
            "ETHL2x"
        );
    }

    function test_Rebalance_SimpleRebalanceSingleLeverageToken_Overcollateralized() public {
        rebalanceAdapter.mockIsEligibleForRebalance(leverageToken, true);
        rebalanceAdapter.mockIsValidStateAfterRebalance(leverageToken, true);

        adapter.mockConvertCollateralToDebtAssetExchangeRate(2_000_00000000); // ETH = 2000 USDC
        adapter.mockCollateral(10 ether); // 10 ETH = 20,000 USDC
        adapter.mockDebt(5_000 ether); // 5,000 USDC

        // Current leverage is 4x and leverageToken needs to be rebalanced, current equity is 15,000 USDC
        uint256 amountToBorrow = 10_000 ether; // 10,000 USDC
        uint256 amountToSupply = 5 ether; // 5 ETH = 10,000 USDC

        WETH.mint(address(this), amountToSupply);

        RebalanceAction[] memory actions = new RebalanceAction[](2);
        actions[0] = RebalanceAction({actionType: ActionType.AddCollateral, amount: amountToSupply});
        actions[1] = RebalanceAction({actionType: ActionType.Borrow, amount: amountToBorrow});

        LeverageTokenState memory stateBefore = leverageManager.getLeverageTokenState(leverageToken);
        LeverageTokenState memory expectedStateAfter = LeverageTokenState({
            collateralInDebtAsset: 30_000 ether, // 15 ETH = 30,000 USDC
            debt: 15_000 ether, // 15,000 USDC
            equity: 15_000 ether, // 15,000 USDC
            collateralRatio: 2 * _BASE_RATIO() // Back to2x leverage
        });

        WETH.approve(address(leverageManager), amountToSupply);

        vm.expectEmit(true, true, true, true);
        emit ILeverageManager.Rebalance(leverageToken, address(this), stateBefore, expectedStateAfter, actions);
        leverageManager.rebalance(
            leverageToken, actions, IERC20(address(WETH)), IERC20(address(USDC)), amountToSupply, amountToBorrow
        );

        LeverageTokenState memory state = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(state.collateralInDebtAsset, expectedStateAfter.collateralInDebtAsset);
        assertEq(state.debt, expectedStateAfter.debt);
        assertEq(state.equity, expectedStateAfter.equity);
        assertEq(state.collateralRatio, expectedStateAfter.collateralRatio);
        assertEq(USDC.balanceOf(address(this)), amountToBorrow); // Rebalancer took debt
    }

    function test_Rebalance_SimpleRebalanceSingleLeverageToken_RebalancerTakesReward_Overcollateralized() public {
        rebalanceAdapter.mockIsEligibleForRebalance(leverageToken, true);
        rebalanceAdapter.mockIsValidStateAfterRebalance(leverageToken, true);

        adapter.mockConvertCollateralToDebtAssetExchangeRate(2_000_00000000); // ETH = 2000 USDC
        adapter.mockCollateral(10 ether); // 10 ETH = 20,000 USDC
        adapter.mockDebt(5_000 ether); // 5,000 USDC

        // Current leverage is 4x and leverageToken needs to be rebalanced, current equity is 15,000 USDC
        uint256 amountToBorrow = 5_000 ether; // 5,000 USDC
        uint256 amountToSupply = 2.25 ether; // 2,25 ETH = 4500 USDC

        WETH.mint(address(this), amountToSupply);

        RebalanceAction[] memory actions = new RebalanceAction[](2);
        actions[0] = RebalanceAction({actionType: ActionType.AddCollateral, amount: amountToSupply});
        actions[1] = RebalanceAction({actionType: ActionType.Borrow, amount: amountToBorrow});

        WETH.approve(address(leverageManager), amountToSupply);
        leverageManager.rebalance(
            leverageToken, actions, IERC20(address(WETH)), IERC20(address(USDC)), amountToSupply, amountToBorrow
        );

        LeverageTokenState memory state = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(state.collateralInDebtAsset, 24_500 ether); // 12,25 ETH = 24,500 USDC
        assertEq(state.debt, 10_000 ether); // 10,000 USDC
        assertEq(state.equity, 14_500 ether); // 14,500 USDC, 10% reward
        assertEq(state.collateralRatio, 245 * _BASE_RATIO() / 100); // Back to 2.45x leverage which is better than 4x
        assertEq(USDC.balanceOf(address(this)), amountToBorrow); // Rebalancer took debt
    }

    function test_Rebalance_SimpleRebalanceSingleLeverageToken_RebalancerTakesReward_Undercollateralized() public {
        rebalanceAdapter.mockIsEligibleForRebalance(leverageToken, true);
        rebalanceAdapter.mockIsValidStateAfterRebalance(leverageToken, true);

        adapter.mockConvertCollateralToDebtAssetExchangeRate(2_000_00000000); // ETH = 2000 USDC, mock ETH price
        adapter.mockCollateral(10 ether); // 10 ETH = 20,000 USDC
        adapter.mockDebt(15_000 ether); // 15,000 USDC

        // Current leverage is 1,333x and leverageToken needs to be rebalanced, current equity is 5,000 USDC
        uint256 amountToRepay = 10_000 ether; // 10,000 USDC
        uint256 amountToRedeem = 5.5 ether; // 5,5 ETH = 11,000 USDC

        USDC.mint(address(this), amountToRepay);

        RebalanceAction[] memory actions = new RebalanceAction[](2);
        actions[0] = RebalanceAction({actionType: ActionType.Repay, amount: amountToRepay});
        actions[1] = RebalanceAction({actionType: ActionType.RemoveCollateral, amount: amountToRedeem});

        USDC.approve(address(leverageManager), amountToRepay);
        leverageManager.rebalance(
            leverageToken, actions, IERC20(address(USDC)), IERC20(address(WETH)), amountToRepay, amountToRedeem
        );

        LeverageTokenState memory state = leverageManager.getLeverageTokenState(leverageToken);
        assertEq(state.collateralInDebtAsset, 9_000 ether); // 4,5 ETH = 9,000 USDC
        assertEq(state.debt, 5_000 ether); // 5,000 USDC
        assertEq(state.equity, 4_000 ether); // 4,500 USDC, 10% reward
        assertEq(state.collateralRatio, 180 * _BASE_RATIO() / 100); // Back to 1,8x leverage which is better than 1,333x
        assertEq(WETH.balanceOf(address(this)), amountToRedeem); // Rebalancer took collateral
    }

    function test_rebalance_RevertIf_NotEligibleForRebalance() external {
        rebalanceAdapter.mockIsEligibleForRebalance(leverageToken, false);

        adapter.mockConvertCollateralToDebtAssetExchangeRate(2_000_00000000); // ETH = 2000 USDC
        adapter.mockCollateral(10 ether); // 10 ETH = 20,000 USDC
        adapter.mockDebt(5_000 ether); // 5,000 USDC

        // Current leverage is 4x and leverageToken needs to be rebalanced, current equity is 15,000 USDC
        uint256 amountToBorrow = 10_000 ether; // 10,000 USDC
        uint256 amountToSupply = 4 ether; // 4 ETH = 8,000 USDC

        WETH.mint(address(this), amountToSupply);

        RebalanceAction[] memory actions = new RebalanceAction[](2);
        actions[0] = RebalanceAction({actionType: ActionType.AddCollateral, amount: amountToSupply});
        actions[1] = RebalanceAction({actionType: ActionType.Borrow, amount: amountToBorrow});

        WETH.approve(address(leverageManager), amountToSupply);

        vm.expectRevert(ILeverageManager.LeverageTokenNotEligibleForRebalance.selector);
        leverageManager.rebalance(
            leverageToken, actions, IERC20(address(WETH)), IERC20(address(USDC)), amountToSupply, amountToBorrow
        );
    }

    function test_rebalance_RevertIf_InvalidStateAfterRebalance() external {
        rebalanceAdapter.mockIsEligibleForRebalance(leverageToken, true);
        rebalanceAdapter.mockIsValidStateAfterRebalance(leverageToken, false);

        adapter.mockConvertCollateralToDebtAssetExchangeRate(2_000_00000000); // ETH = 2000 USDC
        adapter.mockCollateral(10 ether); // 10 ETH = 20,000 USDC
        adapter.mockDebt(5_000 ether); // 5,000 USDC

        // Current leverage is 4x and leverageToken needs to be rebalanced, current equity is 15,000 USDC
        uint256 amountToBorrow = 11_000 ether; // 11,000 USDC
        uint256 amountToSupply = 5.5 ether; // 5,5 ETH = 11,000 USDC

        WETH.mint(address(this), amountToSupply);

        RebalanceAction[] memory actions = new RebalanceAction[](2);
        actions[0] = RebalanceAction({actionType: ActionType.AddCollateral, amount: amountToSupply});
        actions[1] = RebalanceAction({actionType: ActionType.Borrow, amount: amountToBorrow});

        WETH.approve(address(leverageManager), amountToSupply);

        vm.expectRevert(
            abi.encodeWithSelector(ILeverageManager.InvalidLeverageTokenStateAfterRebalance.selector, leverageToken)
        );
        leverageManager.rebalance(
            leverageToken, actions, IERC20(address(WETH)), IERC20(address(USDC)), amountToSupply, amountToBorrow
        );
    }
}
