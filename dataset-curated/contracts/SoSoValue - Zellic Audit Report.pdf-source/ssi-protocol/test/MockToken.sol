// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 decimals_;
    mapping(address => bool) public blockAccounts;

    constructor(string memory name_, string memory symbol_, uint8 decimals__) ERC20(name_, symbol_) {
        decimals_ = decimals__;
    }

    function mint(address account, uint value) external {
        _mint(account, value);
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    function blockAccount(address account, bool flag) external {
        blockAccounts[account] = flag;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blockAccounts[from] && !blockAccounts[to]);
        super._update(from, to, value);
    }
}

contract MockTokens {
    MockToken public WBTC = new MockToken("Wrapped BTC", "WBTC", 8);
    MockToken public WETH = new MockToken("Wrapped ETH", "WETH", 18);
}