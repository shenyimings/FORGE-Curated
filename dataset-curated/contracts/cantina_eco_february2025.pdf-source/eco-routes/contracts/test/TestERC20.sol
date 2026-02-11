/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    function mint(address recipient, uint256 amount) public {
        _mint(recipient, amount);
    }

    function transferPayable(
        address recipient,
        uint256 amount
    ) public payable returns (bool) {
        return transfer(recipient, amount);
    }
}
