// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {IPauser} from "src/interfaces/IPauser.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {Pauser_Unit_Shared} from "../shared/Pauser_Unit_Shared.t.sol";

contract Pauser_pause is Pauser_Unit_Shared {
    function test_WhenContractDoesNotHaveThePAUSE_MANAGERRole() external {
        pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);
        pauser.addPausableMarket(address(mWethExtension), IPauser.PausableType.Extension);

        // it should revert for emergencyPauseAll
        vm.expectRevert(IPauser.Pauser_NotAuthorized.selector);
        pauser.emergencyPauseAll();

        // it should revert for emergencyPauseMarket
        vm.expectRevert(IPauser.Pauser_NotAuthorized.selector);
        pauser.emergencyPauseMarket(address(mWethHost));

        // it should revert for emergencyPauseMarketFor
        vm.expectRevert(IPauser.Pauser_NotAuthorized.selector);
        pauser.emergencyPauseMarketFor(address(mWethHost), ImTokenOperationTypes.OperationType.AmountIn);
    }

    modifier whenContractHasThePAUSE_MANAGERRole() {
        roles.allowFor(address(this), roles.PAUSE_MANAGER(), true);
        roles.allowFor(address(pauser), roles.GUARDIAN_PAUSE(), true);
        _;
    }

    function test_GivenEmergencyPauseMarketIsCalled() external whenContractHasThePAUSE_MANAGERRole {
        pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);

        assertFalse(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint));
        pauser.emergencyPauseMarket(address(mWethHost));
        // it should pause all market operations
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Seize));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Transfer));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem));

        pauser.addPausableMarket(address(mWethExtension), IPauser.PausableType.Extension);
        assertFalse(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Mint));
        pauser.emergencyPauseMarket(address(mWethExtension));
        // it should pause all market operations
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountIn));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountInHere));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountOut));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountOutHere));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Mint));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Seize));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Transfer));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Borrow));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Repay));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Redeem));
    }

    function test_GivenEmergencyPauseMarketForIsCalled() external whenContractHasThePAUSE_MANAGERRole {
        // it should only pause a specific operation type
        pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);
        assertFalse(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint));
        pauser.emergencyPauseMarketFor(address(mWethHost), ImTokenOperationTypes.OperationType.Mint);
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint));
        assertFalse(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem));

        // it should only pause a specific operation type
        pauser.addPausableMarket(address(mWethExtension), IPauser.PausableType.Extension);
        assertFalse(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Mint));
        pauser.emergencyPauseMarketFor(address(mWethExtension), ImTokenOperationTypes.OperationType.Mint);
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Mint));
    }

    function test_GivenEmergencyPauseAllIsCalled() external whenContractHasThePAUSE_MANAGERRole {
        // it should pause all registered markets
        pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);
        pauser.addPausableMarket(address(mWethExtension), IPauser.PausableType.Extension);
        pauser.emergencyPauseAll();

        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Mint));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Seize));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Transfer));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Borrow));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Repay));
        assertTrue(operator.isPaused(address(mWethHost), ImTokenOperationTypes.OperationType.Redeem));

        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountIn));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountInHere));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountOut));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.AmountOutHere));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Seize));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Transfer));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Borrow));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Repay));
        assertTrue(mWethExtension.isPaused(ImTokenOperationTypes.OperationType.Redeem));
    }
}
