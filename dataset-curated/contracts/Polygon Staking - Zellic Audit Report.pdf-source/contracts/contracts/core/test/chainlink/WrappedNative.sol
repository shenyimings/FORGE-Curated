// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrappedNative is ERC20 {
    constructor() ERC20("WrappedNative", "WN") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
}
