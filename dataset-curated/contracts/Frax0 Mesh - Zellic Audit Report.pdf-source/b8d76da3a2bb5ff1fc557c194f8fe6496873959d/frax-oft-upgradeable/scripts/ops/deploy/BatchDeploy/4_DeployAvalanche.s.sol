// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/BatchDeploy/4_DeployAvalanche.s.sol --rpc-url https://api.avax.network/ext/bc/C/rpc
contract DeployAvalanche is DeployFraxOFTProtocol {
    // Skip Sonic dvn setup as horizon dvn does not yet exist
    function setDVNs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public override {
        if (_connectedConfig.dvnHorizen == address(0)) {
            return;
        }
        super.setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: _configs
        });
    }

    // override fraxtal frxUSD, sfrxUSD with standalone lockboxes and
    // (s)frxUSD only to Fraxtal, Ink, Sonic, Arbitrum, Optimism, Polygon
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        require(frxUsdOft != address(0) && sfrxUsdOft != address(0), "ofts are null");
        
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                address peerOft = _peerOfts[o];
                // for fraxtal destination, override oft address of frxUSD/sfrxUSD to the standalone lockboxes
                if (_configs[c].chainid == 252) {
                    if (_connectedOfts[o] == frxUsdOft) {
                        // standalone frxUSD lockbox
                        peerOft = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
                    } else if (_connectedOfts[o] == sfrxUsdOft) {
                        // standalone sfrxUSD lockbox
                        peerOft = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
                    }
                } else {
                    // For frxUSD and sfrxUSD, only additionally set up:
                    if (_connectedOfts[o] == frxUsdOft || _connectedOfts[o] == sfrxUsdOft) {
                        // 1. avalanche => (ink, sonic, arbitrum, optimism, polygon)
                        if (block.chainid == 43114) { // TODO: DOUBLE CHECK THIS EVERY COPY PASTA
                            if (
                                _configs[c].chainid != 57073 && _configs[c].chainid != 146 &&
                                _configs[c].chainid != 42161 && _configs[c].chainid != 10 &&
                                _configs[c].chainid != 137
                            ) {
                                continue;
                            }
                        // 2. (ink, sonic, arbitrum, optimism, polygon) => avalanche
                        } else if (
                            block.chainid != 57073 && block.chainid != 146 &&
                            block.chainid != 42161 && block.chainid != 10 &&
                            block.chainid != 137
                        ) {
                            continue;
                        }
                    }
                }
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(/*_peerOfts[o]*/ peerOft)
                });
            }
        }
    }

}