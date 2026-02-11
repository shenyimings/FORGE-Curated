// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/ops/deploy/DeployRandomAddressOFTs/DeployRandomAddressOFTs.s.sol";

/// @notice Follow the hub model for fraxtal where the only peer is fraxtal
/// @dev same code as `DeployFraxOFTProtocolFraxtalHub.s.sol`
contract DeployRandomAddressOFTsFraxtalHub is DeployRandomAddressOFTs {
    L0Config[] public tempConfigs;

    function run() public override {
        // make proxyOfts only to Fraxtal
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (
                proxyConfigs[i].chainid == 252 ||
                proxyConfigs[i].chainid == broadcastConfig.chainid
            ) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        delete proxyConfigs;
        for (uint256 i=0; i<tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        super.run();
    }
}