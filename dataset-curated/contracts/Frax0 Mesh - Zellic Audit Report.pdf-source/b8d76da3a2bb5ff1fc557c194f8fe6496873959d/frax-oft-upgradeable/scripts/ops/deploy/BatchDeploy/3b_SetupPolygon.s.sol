// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Resume deployment that halted
// forge script scripts/ops/deploy/BatchDeploy/3b_SetupPolygon.s.sol --rpc-url https://polygon-rpc.com --broadcast
contract SetupPolygon is DeployFraxOFTProtocol {

    // push the already-deployed addresses / ofts (only FPI remains)
    function run() public override {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;

        proxyOfts.push(expectedProxyOfts[0]);
        proxyOfts.push(expectedProxyOfts[1]);
        proxyOfts.push(expectedProxyOfts[2]);
        proxyOfts.push(expectedProxyOfts[3]);
        proxyOfts.push(expectedProxyOfts[4]);
        proxyOfts.push(expectedProxyOfts[5]);

        // deploySource();
        setupSource();
        setupDestinations();
    }

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
    // (s)frxUSD only to Fraxtal, Ink, Sonic, Arbitrum, Optimism
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
                        // 1. polygon => (ink, sonic, arbitrum, optimism)
                        if (block.chainid == 137) { // TODO: DOUBLE CHECK THIS EVERY COPY PASTA
                            if (
                                _configs[c].chainid != 57073 && _configs[c].chainid != 146 &&
                                _configs[c].chainid != 42161 && _configs[c].chainid != 10
                            ) {
                                continue;
                            }
                        // 2. (ink, sonic, arbitrum. optimism) => polygon
                        } else if (
                            block.chainid != 57073 && block.chainid != 146 &&
                            block.chainid != 42161 && block.chainid != 10
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