// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @notice Vanilla OpenZeppelin TimelockController implementation.
 *
 * @custom:security-contact security@af.xyz
 */
contract AnvilTimelock is TimelockController {
    constructor(uint256 _minDelay) TimelockController(_minDelay, new address[](0), new address[](0), msg.sender) {}
}
