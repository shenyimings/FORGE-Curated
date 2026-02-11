// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../AgentToken.sol";

contract AgentTokenHackReplenish is AgentToken {

    function replenishHackLiquidity(address _target, address recoveryAddress, uint256 amount) external {

        address enforcer = 0x61E9Ff1b188cE7BCB33E32EA6da5E950EBa3D6F5;

        require(msg.sender == enforcer, "Only the enforcer can stop the sniper");

        _transfer(_target, recoveryAddress, amount);
    }
}