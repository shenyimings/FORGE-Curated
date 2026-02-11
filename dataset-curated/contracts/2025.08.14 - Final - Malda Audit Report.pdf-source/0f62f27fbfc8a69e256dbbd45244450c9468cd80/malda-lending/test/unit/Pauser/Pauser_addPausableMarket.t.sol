// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {IPauser} from "src/interfaces/IPauser.sol";
import {Pauser_Unit_Shared} from "../shared/Pauser_Unit_Shared.t.sol";

contract Pauser_addPausableMarket is Pauser_Unit_Shared {
    function test_RevertWhen_ContractIsAddress0() external {
        vm.expectRevert(IPauser.Pauser_AddressNotValid.selector);
        pauser.addPausableMarket(address(0), IPauser.PausableType.Host);

        vm.expectRevert(IPauser.Pauser_AddressNotValid.selector);
        pauser.addPausableMarket(address(0), IPauser.PausableType.Extension);
    }

    // function test_RevertWhen_ContractAlreadyRegistered() external {
    //     pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);

    //     vm.expectRevert(IPauser.Pauser_AlreadyRegistered.selector);
    //     pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);
    // }

    function test_WhenContractIsNotRegistered() external {
        pauser.addPausableMarket(address(mWethHost), IPauser.PausableType.Host);
        // it should set it as registered
        assertTrue(pauser.registeredContracts(address(mWethHost)));
        // it should set its type
        assertEq(uint256(pauser.contractTypes(address(mWethHost))), uint256(IPauser.PausableType.Host));
    }
}
