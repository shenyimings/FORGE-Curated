/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestERC20} from "./TestERC20.sol";

contract BadERC20 is TestERC20 {
    error TransferNotAllowed();

    address private immutable GOD;

    constructor(
        string memory name_,
        string memory symbol_,
        address _god
    ) TestERC20(name_, symbol_) {
        GOD = _god;
    }

    function transfer(
        address to,
        uint256 value
    ) public override returns (bool) {
        if (msg.sender != GOD) {
            revert TransferNotAllowed();
        }
        return (super.transfer(to, value));
    }
}
