// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {IPauser} from "src/interfaces/IPauser.sol";
import {Pauser_Unit_Shared} from "../shared/Pauser_Unit_Shared.t.sol";

contract Pauser_removePausableMarket is Pauser_Unit_Shared {
    function test_RevertWhen_ContractIsNotRegistered() external {
        vm.expectRevert(IPauser.Pauser_EntryNotFound.selector);
        pauser.removePausableMarket(address(mWethHost));
    }

    function test_WhenContractIsRegistered() external {
        pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);

        // it should remove it from the pausable contracts array
        // it should remove the registered entry
    }
}
