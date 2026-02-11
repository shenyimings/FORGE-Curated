// SPDX-License-Identifier: MIT
// This is a testing contract, not for production use
pragma solidity ^0.8.0;

import "./BMWTokenChild.sol";

contract FxERC20ChildTunnel {
    // Bridge L1->L2
    function syncDeposit(address childToken, uint256 amount) public {
        BMWTokenChild childTokenContract = BMWTokenChild(childToken);
        childTokenContract.mint(msg.sender, amount);
    }

    // Bridge L2->L1
    function withdraw(address childToken, uint256 amount) public {
        BMWTokenChild childTokenContract = BMWTokenChild(childToken);
        childTokenContract.burn(msg.sender, amount);
    }
}
