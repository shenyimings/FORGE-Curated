// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { Vm } from "forge-std/Vm.sol";

contract TimeUtils {
    function _timeTravel(uint256 _seconds) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        vm.warp(block.timestamp + _seconds);
        vm.roll(block.number + _seconds);
    }
}
