// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Delegation} from "./Delegation.sol";

contract Simulation is Delegation {
    function simulateExecute(bytes32 mode, bytes calldata executionData)
        external
        payable
        returns (uint256)
    {
        uint256 gas = gasleft();
        _execute(mode, executionData, true);
        return gas - gasleft();
    }
}
