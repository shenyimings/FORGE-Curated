// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20Burnable, ERC20Permit {
    uint8 private immutable __decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals,
        address owner
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(owner != address(0), "Owner address cannot be zero");
        __decimals = _decimals;
        _mint(owner, 100000000 * (10 ** _decimals));
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function mint(uint256 amount, address receiver) external {
        require(receiver != address(0), "Cannot mint to zero address");
        _mint(receiver, amount);
    }
    // add this to be excluded from coverage report
    function test() public {}
}
