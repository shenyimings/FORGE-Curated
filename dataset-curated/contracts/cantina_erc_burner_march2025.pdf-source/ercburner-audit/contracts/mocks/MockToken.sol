// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {

    string public _name;
    string public _symbol;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _name = name;
        _symbol = symbol;
    }



    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}