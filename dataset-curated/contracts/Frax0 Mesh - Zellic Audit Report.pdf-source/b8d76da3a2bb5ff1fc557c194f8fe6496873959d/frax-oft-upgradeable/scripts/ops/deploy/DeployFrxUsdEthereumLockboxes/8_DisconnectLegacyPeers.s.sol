// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/8_DisconnectLegacyPeers.s.sol --rpc-url https://rpc.frax.com
contract ConnectProxyChains is DeployFraxOFTProtocol {
    using Strings for uint256;

    address[] public emptyPeersArray;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/txs/");

        string memory name = string.concat(simulateConfig.chainid.toString(), "-disconnect-legacy-peers.json");
        return string.concat(root, name);
    }

    function run() public override {

        for (uint256 i=0; i<expectedProxyOfts.length; i++) {
            emptyPeersArray.push(address(0));
        }

        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED);
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E);
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A);
        legacyOfts.push(0x23432452B720C80553458496D4D9d7C5003280d0);
        legacyOfts.push(0xF010a7c8877043681D59AD125EbF575633505942);
        legacyOfts.push(0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d);

        // reset all peers from legacy => proxy chains
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            if (legacyConfigs[c].chainid == 1) continue;
            setEvmPeers({
                _connectedOfts: legacyOfts,
                _peerOfts: emptyPeersArray,
                _configs: proxyConfigs,
                _simulateConfig: legacyConfigs[c]
            });
        }

        // reset all peers from proxy => legacy chains
        for (uint256 c=0; c<proxyConfigs.length; c++) {
            if (proxyConfigs[c].chainid == 252) continue;     
            setEvmPeers({
                _connectedOfts: expectedProxyOfts,
                _peerOfts: emptyPeersArray,
                _configs: legacyConfigs,
                _simulateConfig: proxyConfigs[c]
            });
        }
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs,
        L0Config memory _simulateConfig
    ) public simulateAndWriteTxs(_simulateConfig) {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                if (_configs[c].chainid == 1) continue;

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}