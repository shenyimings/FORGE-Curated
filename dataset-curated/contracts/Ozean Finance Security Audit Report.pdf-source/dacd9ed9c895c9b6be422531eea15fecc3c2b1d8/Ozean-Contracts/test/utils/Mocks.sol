// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

contract TestERC20Decimals is ERC20 {
    constructor(uint8 _decimals) ERC20("TEST", "TST", _decimals) {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }
}

contract TestERC20DecimalsFeeOnTransfer is ERC20 {
    constructor(uint8 _decimals) ERC20("TEST", "TST", _decimals) {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function transfer(address to, uint256 amount) public  override returns (bool) {
        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[to] += (amount - 1);
        }
        emit Transfer(msg.sender, to, amount - 1);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += (amount - 1);
        }
        emit Transfer(from, to, amount - 1);
        return true;
    }
}
