// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title Governance Timelock
 * @notice Proxies owners functions and adds a minimum delay before execution
 */
contract GovernanceTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
