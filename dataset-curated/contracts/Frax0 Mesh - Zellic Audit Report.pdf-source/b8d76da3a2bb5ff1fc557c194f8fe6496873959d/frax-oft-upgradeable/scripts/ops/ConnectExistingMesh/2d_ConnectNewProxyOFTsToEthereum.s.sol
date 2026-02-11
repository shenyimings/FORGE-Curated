// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev Connect upgradeable chains to eth lockboxes - only setup destinations
// forge script scripts/ops/ConnectExistingMesh/2d_ConnectNewProxyOFTsToEthereum.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract ConnectNewProxyOFTsToEthereum is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    L0Config[] public newProxyConfigs;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/ConnectExistingMesh/txs/");
        string memory name = string.concat("2d_ConnectNewProxyOFTsToEthereum-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev setup all (s)frxUSD configs across all chains
    function run() public override {
        // to enable passing of setEvmPeers
        frxUsdOft = address(1);
        sfrxUsdOft = address(1);

        // skip connecting (Mode, Sei, Fraxtal, X-Layer) as they're already connected
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (
                proxyConfigs[i].chainid != 34443 && proxyConfigs[i].chainid != 1329 && 
                proxyConfigs[i].chainid != 252 && proxyConfigs[i].chainid != 196
            ) {
                newProxyConfigs.push(proxyConfigs[i]);
            }
        }

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    function setupProxyDestinations() public override {
        for (uint256 i=0; i<newProxyConfigs.length; i++) {
            // skip if destination == source
            if (newProxyConfigs[i].eid == broadcastConfig.eid) continue;
            setupDestination({
                _connectedConfig: newProxyConfigs[i]
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: ethLockboxes,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });
    }

}