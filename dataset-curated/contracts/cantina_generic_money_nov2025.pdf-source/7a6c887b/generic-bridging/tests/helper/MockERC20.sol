// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IERC20Mintable } from "../../src/interfaces/IERC20Mintable.sol";

contract MockERC20 is IERC20Mintable, ERC20 {
    uint8 private _decimals;

    constructor(uint8 decimals_) ERC20("Mock USD", "M-USD") {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function burn(address from, address spender, uint256 amount) external {
        if (msg.sender != from) _spendAllowance(from, spender, amount);
        _burn(from, amount);
        emit Burn(from, amount);
    }
}
