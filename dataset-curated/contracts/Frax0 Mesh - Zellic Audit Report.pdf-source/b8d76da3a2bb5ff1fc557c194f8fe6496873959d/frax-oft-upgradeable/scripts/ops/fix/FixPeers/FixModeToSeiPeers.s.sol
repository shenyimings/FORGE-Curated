// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// connect mode to sei peers
// forge script scripts/ops/fix/FixPeers/FixModeToSeiPeers.s.sol --rpc-url https://mainnet.mode.network/
contract FixModeToSeiPeers is DeployFraxOFTProtocol {

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(root, "/scripts/ops/fix/FixPeers/txs/FixModeToSeiPeers.json");
        return name;
    }


    function run() public override simulateAndWriteTxs(broadcastConfig) {
        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                
                // skip if not sei
                if (_configs[c].chainid != 1329) continue;
                
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}