// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";

contract FeeERC20 is ERC20Mock {
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            _burn(to, amount / 100); // simulate 1% transfer fee
        }
    }
}
