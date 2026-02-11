// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IERC20Mintable.sol";

contract RCH is ERC20Burnable, ERC20Permit, IERC20Mintable, Ownable {
    uint256 public constant MAX_SUPPLY = 37_000_000 ether;
    uint256 public immutable tradingStartTime;
    uint256 public totalMinted;

    constructor(uint256 tradingStartTime_) ERC20("RCH Token", "RCH") ERC20Permit("RCH") {
        tradingStartTime = tradingStartTime_;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        if (block.timestamp < tradingStartTime) {
            require(tx.origin == owner() || _msgSender() == owner(), "RCH: token transfer not allowed before trading starts");
        }
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalMinted + amount <= MAX_SUPPLY, "RCH: cap exceeded");

        totalMinted += amount;
        _mint(to, amount);
    }
}
