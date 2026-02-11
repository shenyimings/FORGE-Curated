// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 decimals_;
    constructor(string memory name_, string memory symbol_, uint8 decimals__) ERC20(name_, symbol_) {
        decimals_ = decimals__;
    }

    function mint(address account, uint value) external {
        _mint(account, value);
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }
}

contract MockTokens {
    MockToken public WBTC = new MockToken("Wrapped BTC", "WBTC", 8);
    MockToken public WETH = new MockToken("Wrapped ETH", "WETH", 18);
}