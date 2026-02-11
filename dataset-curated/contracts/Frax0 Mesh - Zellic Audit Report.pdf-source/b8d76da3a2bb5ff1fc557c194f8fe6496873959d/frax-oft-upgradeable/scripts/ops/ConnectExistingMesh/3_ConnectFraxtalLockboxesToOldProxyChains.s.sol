// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev connect [Mode, Sei, X-Layer] (s)FRAX to fraxtal (s)frxUSD lockboxes
// forge script scripts/ops/ConnectExistingMesh/3_ConnectFraxtalLockboxesToOldProxyChains.s.sol --rpc-url https://rpc.frax.com
contract ConnectFraxtalLockboxesToOldProxyChains is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    L0Config[] oldProxyConfigs;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/ConnectExistingMesh/txs/");
        string memory name = string.concat("3_ConnectFraxtalLockboxesToOldProxyChains-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev setup all (s)frxUSD configs across all chains
    function run() public override {
        // to enable passing of setEvmPeers
        frxUsdOft = address(1);
        sfrxUsdOft = address(1);

        // only add sei, mode, xlayer proxy config
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (
                proxyConfigs[i].chainid == 34443 || proxyConfigs[i].chainid == 1329 ||
                proxyConfigs[i].chainid == 196
            ) {
                oldProxyConfigs.push(proxyConfigs[i]);
            }
        }

        // [frxUsd, sfrxUsd]
        delete fraxtalLockboxes;
        fraxtalLockboxes.push(fraxtalFrxUsdLockbox);
        fraxtalLockboxes.push(fraxtalSFrxUsdLockbox);

        delete proxyOfts;
        proxyOfts.push(proxyFrxUsdOft);
        proxyOfts.push(proxySFrxUsdOft);

        // deploySource();
        setupSource();
        setupDestinations();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: fraxtalLockboxes,
            _configs: oldProxyConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: fraxtalLockboxes,
            _configs: oldProxyConfigs
        });

        // setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: fraxtalLockboxes,
            _configs: oldProxyConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: fraxtalLockboxes,
            _peerOfts: proxyOfts,
            _configs: oldProxyConfigs
        });
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    function setupProxyDestinations() public override {
        for (uint256 i=0; i<oldProxyConfigs.length; i++) {
            // skip if destination == source
            if (oldProxyConfigs[i].eid == broadcastConfig.eid) continue;
            setupDestination({
                _connectedConfig: oldProxyConfigs[i]
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: fraxtalLockboxes,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: proxyOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: proxyOfts,
            _configs: broadcastConfigArray
        });
    }

}