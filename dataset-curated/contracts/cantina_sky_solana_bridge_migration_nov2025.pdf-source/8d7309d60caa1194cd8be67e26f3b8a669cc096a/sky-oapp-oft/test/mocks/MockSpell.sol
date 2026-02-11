// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { MockControlledContract } from "./MockControlledContract.sol";

contract MockSpell {
    MockControlledContract public immutable controlledContract;

    error CallFailed();

    constructor(MockControlledContract _controlledContract) {
        controlledContract = _controlledContract;
    }

    function cast() public {
        controlledContract.setData("test message");
    }
}