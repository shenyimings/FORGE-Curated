// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {RebalanceAction, ActionType} from "src/types/DataTypes.sol";

contract TransferTokensTest is LeverageManagerTest {
    function setUp() public override {
        super.setUp();
    }

    function test_IsElementInSlice() public view {
        RebalanceAction[] memory actions = new RebalanceAction[](4);

        actions[0] = RebalanceAction({
            leverageToken: ILeverageToken(address(0)),
            actionType: ActionType.AddCollateral,
            amount: 100
        });
        actions[1] = RebalanceAction({
            leverageToken: ILeverageToken(address(1)),
            actionType: ActionType.AddCollateral,
            amount: 100
        });
        actions[2] = RebalanceAction({
            leverageToken: ILeverageToken(address(2)),
            actionType: ActionType.AddCollateral,
            amount: 100
        });
        actions[3] = RebalanceAction({
            leverageToken: ILeverageToken(address(3)),
            actionType: ActionType.AddCollateral,
            amount: 100
        });

        assertEq(leverageManager.exposed_isElementInSlice(actions, ILeverageToken(address(0)), 1), true);
        assertEq(leverageManager.exposed_isElementInSlice(actions, ILeverageToken(address(2)), 4), true);
        assertEq(leverageManager.exposed_isElementInSlice(actions, ILeverageToken(address(0)), 0), false);
        assertEq(leverageManager.exposed_isElementInSlice(actions, ILeverageToken(address(2)), 2), false);
    }
}
