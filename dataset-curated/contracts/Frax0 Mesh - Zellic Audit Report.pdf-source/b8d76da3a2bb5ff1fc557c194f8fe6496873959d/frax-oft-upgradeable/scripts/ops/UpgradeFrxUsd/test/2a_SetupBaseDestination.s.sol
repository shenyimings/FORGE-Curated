// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMock } from "contracts/mocks/OFTUpgradeableMock.sol";

// forge script scripts/UpgradeFrax/test/2a_SetupBaseDestination.s.sol --rpc-url https://mainnet.base.org
contract SetupBaseDestination is DeployFraxOFTProtocol {

    /// @dev set mock CAC as peer
    function setUp() public virtual override {
        loadJsonConfig();

        delete legacyOfts;
        legacyOfts.push(0xa536976c9cA36e74Af76037af555eefa632ce469); // base adapter

        delete proxyOfts;
        proxyOfts.push(0x8d8F779e1548B0eF538f5Dfe76AbFA232d705C8b); // fraxtal mCAC
    }

    function run() public override {
        setupDestinations();
    }

    function setupDestinations() public override {
        setupLegacyDestinations();
        // setupProxyDestinations();
    }


    function setupLegacyDestinations() public override {
        for (uint256 i=0; i<legacyConfigs.length; i++) {
            // only for base
            if (legacyConfigs[i].chainid != 8453) continue;
            setupDestination({
                _connectedConfig: legacyConfigs[i],
                _connectedOfts: legacyOfts
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public /* simulateAndWriteTxs(_connectedConfig) */ broadcastAs(configDeployerPK) {
        _connectedConfig = _connectedConfig; // warning
        
        // setEvmEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal
        // });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal 
        });

        // setDVNs({
        //     _connectedConfig: broadcastConfig,
        //     _connectedOfts: _connectedOfts,
        //     _configs: /* broadcastConfigArray */ proxyConfigs // includes fraxtal
        // });
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                // only for fraxtal
                if (_configs[c].chainid != 252) continue;
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }
}