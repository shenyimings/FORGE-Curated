// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name__, string memory symbol__) ERC20(name__,symbol__) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
