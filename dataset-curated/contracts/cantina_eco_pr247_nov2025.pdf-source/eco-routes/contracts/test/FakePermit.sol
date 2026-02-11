// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract FakePermit {
    function allowance(
        address,
        address,
        address
    ) external pure returns (uint160, uint48, uint48) {
        return (type(uint160).max, 0, 0); // lie: “unlimited allowance”
    }

    function transferFrom(address, address, uint160, address) external pure {
        // solhint-disable-previous-line no-unused-vars
        // Mock implementation - intentionally empty
        return;
    }
}
