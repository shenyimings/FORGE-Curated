// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MockRoles {
    mapping(address => bool) public permissions;

    bytes32 public constant GUARDIAN_BLACKLIST = keccak256("GUARDIAN_BLACKLIST");

    function isAllowedFor(address account, bytes32) external view returns (bool) {
        return permissions[account];
    }

    function setAllowed(address account, bool allowed) external {
        permissions[account] = allowed;
    }
}
