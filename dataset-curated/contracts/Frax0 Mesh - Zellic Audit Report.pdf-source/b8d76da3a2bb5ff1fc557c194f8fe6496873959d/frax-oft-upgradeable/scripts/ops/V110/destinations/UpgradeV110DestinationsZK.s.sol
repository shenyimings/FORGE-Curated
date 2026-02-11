pragma solidity ^0.8.0;

import {UpgradeV110Destinations, L0Config} from "./UpgradeV110Destinations.s.sol";


contract UpgradeV110DestinationsZK is UpgradeV110Destinations {

    function run() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            L0Config memory proxyConfig = proxyConfigs[i];
            if (proxyConfig.chainid == 252) continue; // Separate script for Fraxtal
            if (proxyConfig.chainid != 324 && proxyConfig.chainid != 2741) continue; // Separate script for zk-chains

            upgradeToV110(proxyConfig);
        }
    }
}