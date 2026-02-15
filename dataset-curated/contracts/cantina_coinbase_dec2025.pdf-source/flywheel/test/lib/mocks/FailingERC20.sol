// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title FailingERC20
/// @notice An ERC20 token that always fails transfers
contract FailingERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false; // Always fail transfers
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false; // Always fail transfers
    }
}
