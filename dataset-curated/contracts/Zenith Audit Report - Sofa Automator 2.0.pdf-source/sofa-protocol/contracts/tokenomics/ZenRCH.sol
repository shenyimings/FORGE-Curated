// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IStRCH.sol";

contract ZenRCH is ERC20, ReentrancyGuard {
    IERC20 public immutable rch;
    IStRCH public immutable stRCH;
    uint256 public constant MINIMUM_SHARES = 10**3;

    event Minted(address indexed account, uint256 amount, uint256 shares);
    event Burned(address indexed account, uint256 amount, uint256 shares);

    constructor(
        IERC20 _rch,
        IStRCH _stRCH
    ) ERC20("Zen RCH", "zRCH") {
        rch = _rch;
        stRCH = _stRCH;
        rch.approve(address(stRCH), type(uint256).max);
    }

    function mint(uint256 amount) external nonReentrant returns (uint256 shares) {
        rch.transferFrom(_msgSender(), address(this), amount);
        stRCH.mint(amount);
        uint256 stRCHBalance = stRCH.balanceOf(address(this));
        if (totalSupply() > 0) {
            shares = amount * totalSupply() / (stRCHBalance - amount);
        } else {
            shares = stRCHBalance - MINIMUM_SHARES;
            _mint(address(0x000000000000000000000000000000000000dEaD), MINIMUM_SHARES);
        }
        _mint(_msgSender(), shares);

        emit Minted(_msgSender(), amount, shares);
    }

    function withdraw(address to, uint256 shares) external nonReentrant returns (uint256 amount) {
        amount = shares * stRCH.balanceOf(address(this)) / totalSupply();
        _burn(_msgSender(), shares);
        stRCH.withdraw(to, amount);

        emit Burned(_msgSender(), amount, shares);
    }
}
