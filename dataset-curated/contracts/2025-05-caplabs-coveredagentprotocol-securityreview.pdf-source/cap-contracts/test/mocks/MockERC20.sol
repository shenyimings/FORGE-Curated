// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    uint256 public constant MAX_MINT = 1e50;
    uint256 public constant MAX_TOTAL_SUPPLY = 1e50;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        require(amount <= MAX_MINT, "Amount must be less than MAX_MINT");

        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mockDecimals(uint8 decimals_) external {
        require(decimals_ <= 50, "Decimals must be less than 50");
        _decimals = decimals_;
    }

    function mockMinimumTotalSupply(uint256 totalSupply_) external {
        require(totalSupply_ <= MAX_TOTAL_SUPPLY, "Total supply must be less than MAX_TOTAL_SUPPLY");

        if (totalSupply_ > totalSupply()) {
            _mint(address(this), totalSupply_ - totalSupply());
        }
    }
}
