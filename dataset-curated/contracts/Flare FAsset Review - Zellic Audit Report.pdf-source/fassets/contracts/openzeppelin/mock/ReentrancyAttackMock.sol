// SPDX-License-Identifier: MIT
// solhint-disable gas-custom-errors

pragma solidity ^0.8.0;

contract ReentrancyAttackMock {
    function callSender(bytes4 data) public {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = msg.sender.call(abi.encodeWithSelector(data));
        require(success, "ReentrancyAttack: failed call");
    }
}
