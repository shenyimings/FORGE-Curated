// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
		_mint(msg.sender, 10_000_000 * 10 ** 18);
	}
}
