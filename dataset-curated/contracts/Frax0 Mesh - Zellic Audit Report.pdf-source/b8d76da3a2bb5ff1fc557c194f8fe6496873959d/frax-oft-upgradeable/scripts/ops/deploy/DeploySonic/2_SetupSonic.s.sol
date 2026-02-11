// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev deployment paused at library setup- resume deployment
// forge script scripts/DeploySonic/2_SetupSonic.s.sol --rpc-url https://rpc.soniclabs.com
contract SetupSonic is DeployFraxOFTProtocol {

    function run() public override {

        // already deployed
        // deploySource();

        // since ofts are already deployed, manually populate the addresses for setup
        proxyOfts.push(expectedProxyOfts[0]);
        proxyOfts.push(expectedProxyOfts[1]);
        proxyOfts.push(expectedProxyOfts[2]);
        proxyOfts.push(expectedProxyOfts[3]);
        proxyOfts.push(expectedProxyOfts[4]);
        proxyOfts.push(expectedProxyOfts[5]);

        // manually set already-deployed contracts
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;

        setupSource();
        setupDestinations();
    }

    /// @dev skip setting DVNs
    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        // setDVNs({
        //     _connectedConfig: broadcastConfig,
        //     _connectedOfts: proxyOfts,
        //     _configs: allConfigs
        // });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setPriviledgedRoles();
    }

    // override fraxtal frxUSD, sfrxUSD with standalone lockboxes
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
                    // For frxUSD and sfrxUSD, only additionally set up Ink source
                    if (_connectedOfts[o] == frxUsdOft || _connectedOfts[o] == sfrxUsdOft) {
                        if (block.chainid != 57073) {
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