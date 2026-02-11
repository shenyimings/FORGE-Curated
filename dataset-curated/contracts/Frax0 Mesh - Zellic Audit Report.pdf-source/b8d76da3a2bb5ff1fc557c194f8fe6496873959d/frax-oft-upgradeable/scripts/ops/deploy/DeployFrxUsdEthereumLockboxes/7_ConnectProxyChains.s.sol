// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/7_ConnectProxyChains.s.sol --rpc-url https://rpc.frax.com
contract ConnectProxyChains is DeployFraxOFTProtocol {
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/txs/");

        string memory name = string.concat(simulateConfig.chainid.toString(), "-connect-proxy-chains.json");
        return string.concat(root, name);
    }

    function run() public override {
        delete expectedProxyOfts;
        expectedProxyOfts.push(proxyFrxUsdOft);
        expectedProxyOfts.push(proxySFrxUsdOft);

        for (uint256 c=0; c<proxyConfigs.length; c++) {
            if (proxyConfigs[c].chainid == 252) continue;     
            setEvmPeers({
                _connectedOfts: expectedProxyOfts,
                _peerOfts: expectedProxyOfts,
                _configs: proxyConfigs,
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

                // skip writing to fraxtal as it is already connected
                if (_configs[c].chainid == 252) continue;

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}