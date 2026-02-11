// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev now that the x-layer oft is deployed, connect fraxtal oft
// forge script scripts/UpgradeFrax/test/setup/3b_SetupFraxtalOFT.s.sol --rpc-url https://rpc.frax.com
contract SetupFraxtalOFT is DeployFraxOFTProtocol {
    address fraxtalOft = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e;
    address xlayerOft = 0x45682729Bdc0f68e7A02E76E9CfdA57D0cD4d20b;

    constructor() {
        delete connectedOfts;
        connectedOfts.push(fraxtalOft);
        proxyOfts.push(xlayerOft);
    }

    function run() public override {
        // deploySource();
        // setupSource();
        setupDestinations();   
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    function setupProxyDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == broadcastConfig.eid) continue;
            // skip if not xlayer
            if (proxyConfigs[i].chainid != 196) continue;
            setupDestination(proxyConfigs[i], connectedOfts);
        }
    }

    function setupDestination(
        L0Config memory /* _connectedConfig */,
        address[] memory _connectedOfts
    ) public /* simulateAndWriteTxs(_connectedConfig) */ broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes xlayer
        });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes xlayer 
        });

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes xlayer
        });
    }
}