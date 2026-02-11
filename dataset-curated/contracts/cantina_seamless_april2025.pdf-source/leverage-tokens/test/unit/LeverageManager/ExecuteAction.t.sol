// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {MockLendingAdapter} from "test/unit/mock/MockLendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ActionType, LeverageTokenConfig} from "src/types/DataTypes.sol";

contract ExecuteActionTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();

        _createNewLeverageToken(
            manager,
            2e18,
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                rebalanceAdapter: IRebalanceAdapterBase(address(0)),
                depositTokenFee: 0,
                withdrawTokenFee: 0
            }),
            address(collateralToken),
            address(debtToken),
            "dummy name",
            "dummy symbol"
        );
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_executeLendingAdapterAction_AddCollateral(uint256 amount) public {
        collateralToken.mint(address(leverageManager), amount);
        leverageManager.exposed_executeLendingAdapterAction(leverageToken, ActionType.AddCollateral, amount);

        assertEq(collateralToken.balanceOf(address(leverageManager)), 0);
        assertEq(
            collateralToken.balanceOf(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken))), amount
        );
    }

    /// forge-config: default.fuzz.runs = 1
    function tesFuzz_executeLendingAdapterAction_RemoveCollateral(uint256 amount) public {
        leverageManager.exposed_executeLendingAdapterAction(leverageToken, ActionType.RemoveCollateral, amount);

        assertEq(collateralToken.balanceOf(address(leverageManager)), amount);
        assertEq(collateralToken.balanceOf(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken))), 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_executeLendingAdapterAction_Repay(uint256 amount) public {
        vm.prank(address(leverageManager));
        lendingAdapter.borrow(amount);

        leverageManager.exposed_executeLendingAdapterAction(leverageToken, ActionType.Repay, amount);

        assertEq(debtToken.balanceOf(address(leverageManager)), 0);
        assertEq(debtToken.balanceOf(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken))), amount);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_executeLendingAdapterAction_Borrow(uint256 amount) public {
        leverageManager.exposed_executeLendingAdapterAction(leverageToken, ActionType.Borrow, amount);

        assertEq(debtToken.balanceOf(address(leverageManager)), amount);
        assertEq(debtToken.balanceOf(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken))), 0);
    }
}
