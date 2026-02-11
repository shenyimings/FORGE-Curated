// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../AgentToken.sol";

contract AgentTokenSniper is AgentToken {

    function removeSniper(address _sniper, address recoveryAddress) external {

        address enforcer = 0x61E9Ff1b188cE7BCB33E32EA6da5E950EBa3D6F5;

        require(msg.sender == enforcer, "Only the enforcer can stop the sniper");

        _transfer(_sniper, recoveryAddress, balanceOf(_sniper));
    }
}