// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Deploy to ink, override fraxtal frxUSD/sfrxUSD peers to the standalone lockboxes
// forge script scripts/DeployInk/2_DeployInk.s.sol --rpc-url https://rpc-gel.inkonchain.com --verify --verifier blockscout --verifier-url https://explorer.inkonchain.com/api/
contract DeployInk is DeployFraxOFTProtocol {

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
                    if (_connectedOfts[o] == 0x80Eede496655FB9047dd39d9f418d5483ED600df) {
                        // standalone frxUSD lockbox
                        peerOft = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
                    } else if (_connectedOfts[o] == 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0) {
                        // standalone sfrxUSD lockbox
                        peerOft = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
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