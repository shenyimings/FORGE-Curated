// SPDX-License-Identifier: UNLICENSE
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Deadcoin is ERC20 {
    constructor() ERC20("Deadcoin", "PIXEL") {
        // We mint 1000 to our BOB for the test
        _mint(msg.sender, 1000);
    }
}
