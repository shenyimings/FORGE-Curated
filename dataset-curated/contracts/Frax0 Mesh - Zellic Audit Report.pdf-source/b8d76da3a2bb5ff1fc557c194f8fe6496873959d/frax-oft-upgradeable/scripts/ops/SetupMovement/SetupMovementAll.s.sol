// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./SetupMovementSingle.s.sol";

// Used to setup all destinations to Movement
// forge script scripts/ops/SetupMovement/SetupMovementAll.s.sol
contract SetupMovementAll is SetupMovementSingle {

    function setupMovementDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            setupMovementDestination(proxyConfigs[i]);
        }
    }

}