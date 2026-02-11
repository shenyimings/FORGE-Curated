// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimelockFactory {
    function deploy(uint256 _minDelaySeconds, address _proposer, address _executor)
        external
        returns (address timelock)
    {
        address[] memory proposers = new address[](1);
        proposers[0] = _proposer;

        address[] memory executors = new address[](1);
        executors[0] = _executor;

        timelock = address(new TimelockController(_minDelaySeconds, proposers, executors, address(0)));
    }
}
