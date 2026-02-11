// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./SetupAptosSingle.s.sol";

// Used to setup all destinations to Aptos
// forge script scripts/ops/SetupAptos/SetupAptosSingle.s.sol
contract SetupAptosAll is SetupAptosSingle {

    function setupAptosDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            setupAptosDestination(proxyConfigs[i]);
        }
    }

}