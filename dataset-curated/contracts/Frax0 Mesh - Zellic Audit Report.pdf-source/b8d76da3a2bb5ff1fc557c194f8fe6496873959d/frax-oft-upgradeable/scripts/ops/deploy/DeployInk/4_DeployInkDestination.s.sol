// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Resume Ink deployment by setting config
// forge script scripts/DeployInk/4_DeployInkDestination.s.sol --rpc-url https://rpc-gel.inkonchain.com
contract DeployInkDestination is DeployFraxOFTProtocol {


    function run() public override {

        // deploySource();

        // since ofts are already deployed, manually populate the addresses for setup
        proxyOfts.push(expectedProxyOfts[0]);
        proxyOfts.push(expectedProxyOfts[1]);
        proxyOfts.push(expectedProxyOfts[2]);
        proxyOfts.push(expectedProxyOfts[3]);
        proxyOfts.push(expectedProxyOfts[4]);
        proxyOfts.push(expectedProxyOfts[5]);

        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;

        // setupSource();
        setupDestinations();
    }

    // override fraxtal frxUSD, sfrxUSD with standalone lockboxes
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
                address peerOft = _peerOfts[o];
                // for fraxtal, override oft address of frxUSD/sfrxUSD to the standalone lockboxes
                if (_configs[c].chainid == 252) {
                    if (_connectedOfts[o] == frxUsdOft) {
                        // standalone frxUSD lockbox
                        peerOft = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
                    } else if (_connectedOfts[o] == sfrxUsdOft) {
                        // standalone sfrxUSD lockbox
                        peerOft = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
                    }
                } else {
                    // if not fraxtal, do not setup peer for frxUSD or sfrxUSD
                    if (_connectedOfts[o] == frxUsdOft || _connectedOfts[o] == sfrxUsdOft) {
                        continue;
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