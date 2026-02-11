// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {IRoles} from "src/interfaces/IRoles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BridgeMock {
    IRoles public roles;

    error BaseBridge_NotAuthorized();

    constructor(address _roles) {
        roles = IRoles(_roles);
    }

    modifier onlyRebalancer() {
        if (!roles.isAllowedFor(msg.sender, roles.REBALANCER())) revert BaseBridge_NotAuthorized();
        _;
    }

    function sendMsg(uint256, address, uint32, address _token, bytes memory _message, bytes memory)
        external
        payable
        onlyRebalancer
    {
        uint256 amount = abi.decode(_message, (uint256));
        IERC20(_token).transferFrom(msg.sender, address(this), amount);
    }
}
