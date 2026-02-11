// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/DeployRemainingEthereumLockboxes/2_RemoveLegacyLockboxPeers.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract RemoveLegacyLockboxPeers is DeployFraxOFTProtocol {
    using Strings for uint256;

    address[] public emptyPeersArray;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployRemainingEthereumLockboxes/txs/");

        string memory name = string.concat(simulateConfig.chainid.toString(), "-disconnect-peers.json");
        return string.concat(root, name);
    }

    function _populateConnectedOfts() public pure override {}

    function run() public override {

        for (uint256 i=0; i<ethLockboxesLegacy.length; i++) {
            emptyPeersArray.push(address(0));
        }

        // reset all peers from ethereum legacy => proxy chains
        setEvmPeers({
            _connectedOfts: ethLockboxesLegacy,
            _peerOfts: emptyPeersArray,
            _configs: proxyConfigs,
            _simulateConfig: broadcastConfig
        });
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