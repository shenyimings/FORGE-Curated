// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Set base peers to zero address
// forge script scripts/ops/fix/FixPeers/FixBaseSolanaPeers.s.sol --rpc-url https://mainnet.base.org
contract FixBaseSolanaPeers is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    address[] public zeroAddressPeers;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(
            root,
            "/scripts/ops/fix/FixPeers/txs/FixBaseSolanaPeers.json"
        );
        return name;
    }

    function _populateConnectedOfts() public override {}

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        for (uint256 i = 0; i < baseProxyOfts.length; i++) {
            zeroAddressPeers.push(address(0));
        }

        setNonEvmPeers(baseProxyOfts);
    }

    function setNonEvmPeers(address[] memory _connectedOfts) public override {
        require(
            _connectedOfts.length == zeroAddressPeers.length,
            "Must wire equal amount of source + dest addrs"
        );
        // Set the peer per OFT
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            address peerOft = zeroAddressPeers[o];
            
            // For each non-evm
            for (uint256 c = 0; c < nonEvmPeersArrays.length; c++) {
                setPeer({
                    _config: nonEvmConfigs[0],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}
