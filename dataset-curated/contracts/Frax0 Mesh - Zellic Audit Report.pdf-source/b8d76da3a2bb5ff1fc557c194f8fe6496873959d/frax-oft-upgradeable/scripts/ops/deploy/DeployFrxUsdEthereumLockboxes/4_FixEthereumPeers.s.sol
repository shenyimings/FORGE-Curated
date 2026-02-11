// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/4_FixEthereumPeers.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract FixEthereumPeers is DeployFraxOFTProtocol {
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, "-fix.json");
        return string.concat(root, name);
    }

    function run() public override {
        frxUsdOft = ethFrxUsdLockbox;
        sfrxUsdOft = ethSFrxUsdLockbox;

        delete expectedProxyOfts;
        expectedProxyOfts.push(proxyFrxUsdOft);
        expectedProxyOfts.push(proxySFrxUsdOft);

        delete ethLockboxes;
        ethLockboxes.push(ethFrxUsdLockbox);
        ethLockboxes.push(ethSFrxUsdLockbox);

        setEvmPeers({
            _connectedOfts: ethLockboxes,
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override simulateAndWriteTxs(broadcastConfig) {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        require(frxUsdOft != address(0) && sfrxUsdOft != address(0), "(s)frxUSD ofts are null");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {

                // for fraxtal destination, override OFT address of (s)frxUSD to the standalone lockbox
                if (_configs[c].chainid == 252) {
                    if (_connectedOfts[o] == frxUsdOft) {
                        peerOft = fraxtalFrxUsdLockbox;
                    } else if (_connectedOfts[o] == sfrxUsdOft) {
                        peerOft = fraxtalSFrxUsdLockbox;
                    } else {
                        require(0==1, "unidentified oft to fraxtal");
                    }
                } else {
                    if (_connectedOfts[o] == frxUsdOft) {
                        peerOft = proxyFrxUsdOft;
                    } else if (_connectedOfts[o] == sfrxUsdOft) {
                        peerOft = proxySFrxUsdOft;
                    } else {
                        require(0==1, "unidentified predetermined peer");
                    }
                }

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}