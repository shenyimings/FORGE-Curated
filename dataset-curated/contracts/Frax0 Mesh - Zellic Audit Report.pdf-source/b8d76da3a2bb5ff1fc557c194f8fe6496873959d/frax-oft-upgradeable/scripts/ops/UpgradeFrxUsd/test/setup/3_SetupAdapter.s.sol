// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev now that the oft is deployed, setup the adapter
// forge script scripts/UpgradeFrax/test/setup/3_SetupAdapter.s.sol --rpc-url https://mainnet.base.org
contract SetupAdapter is DeployFraxOFTProtocol {
    address oft = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e;
    address adapter = 0xa536976c9cA36e74Af76037af555eefa632ce469;


    constructor() {
        delete connectedOfts;
        connectedOfts.push(adapter);
        proxyOfts.push(oft);
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
            // skip if not fraxtal
            if (proxyConfigs[i].chainid != 252) continue;
            setupDestination(proxyConfigs[i], connectedOfts);
        }
    }

    function setupDestination(
        L0Config memory /* _connectedConfig */,
        address[] memory _connectedOfts
    ) public /* simulateAndWriteTxs(_connectedConfig) */ broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal
        });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal 
        });

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: _connectedOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal
        });
    }
}