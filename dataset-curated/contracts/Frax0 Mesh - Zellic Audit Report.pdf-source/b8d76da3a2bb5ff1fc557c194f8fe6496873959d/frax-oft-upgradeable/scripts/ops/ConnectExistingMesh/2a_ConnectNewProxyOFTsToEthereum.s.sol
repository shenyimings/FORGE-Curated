// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev Connect upgradeable chains to eth lockboxes - source - only sets up EVMs
// forge script scripts/ops/ConnectExistingMesh/2a_ConnectNewProxyOFTsToEthereum.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract ConnectNewProxyOFTsToEthereum is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    L0Config[] public newProxyConfigs;

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/ConnectExistingMesh/txs/");
        string memory name = string.concat("2a_ConnectNewProxyOFTsToEthereum-", simulateConfig.chainid.toString());
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
        setupSource();
        // setupDestinations();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: ethLockboxes,
            _configs: newProxyConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: ethLockboxes,
            _peerOfts: expectedProxyOfts,
            _configs: newProxyConfigs
        });
    }
}