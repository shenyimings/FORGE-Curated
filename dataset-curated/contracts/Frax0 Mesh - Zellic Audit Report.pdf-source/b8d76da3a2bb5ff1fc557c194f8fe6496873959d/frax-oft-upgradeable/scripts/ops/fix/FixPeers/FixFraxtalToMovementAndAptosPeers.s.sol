// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// connect fraxtal to aptos & movement peers
// forge script scripts/ops/fix/FixPeers/FixFraxtalToMovementAndAptosPeers.s.sol --rpc-url https://rpc.frax.com
contract FixFraxtalToMovementAndAptosPeers is DeployFraxOFTProtocol {
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(
            root,
            "/scripts/ops/fix/FixPeers/txs/FixFraxtalToMovementAndAptosPeers.json"
        );
        return name;
    }

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        setNonEvmPeers(fraxtalLockboxes);
    }

    function _populateConnectedOfts() public override {}

    function setNonEvmPeers(address[] memory _connectedOfts) public override {
        require(_connectedOfts.length == fraxtalLockboxes.length, "Must wire equal amount of source + dest addrs");
        // Set the peer per OFT for movement
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            // For movement
            setPeer({
                _config: nonEvmConfigs[1],
                _connectedOft: _connectedOfts[o],
                _peerOftAsBytes32: nonEvmPeersArrays[1][o]
            });
        }
        // Set the peer per OFT for aptos
        for (uint256 o = 0; o < _connectedOfts.length; o++) {
            setPeer({
                _config: nonEvmConfigs[2],
                _connectedOft: _connectedOfts[o],
                _peerOftAsBytes32: nonEvmPeersArrays[1][o]
            });
        }
    }

    function setPeer(L0Config memory _config, address _connectedOft, bytes32 _peerOftAsBytes32) public override {
        // cannot set peer to self
        if (block.chainid == _config.chainid) return;
        bytes32 existingPeer = IOAppCore(_connectedOft).peers(uint32(_config.eid));

        if (existingPeer != _peerOftAsBytes32) {
            bytes memory data = abi.encodeCall(IOAppCore.setPeer, (uint32(_config.eid), _peerOftAsBytes32));
            (bool success, ) = _connectedOft.call(data);
            require(success, "Unable to setPeer");
            serializedTxs.push(SerializedTx({ name: "setPeer", to: _connectedOft, value: 0, data: data }));
        }
    }
}
