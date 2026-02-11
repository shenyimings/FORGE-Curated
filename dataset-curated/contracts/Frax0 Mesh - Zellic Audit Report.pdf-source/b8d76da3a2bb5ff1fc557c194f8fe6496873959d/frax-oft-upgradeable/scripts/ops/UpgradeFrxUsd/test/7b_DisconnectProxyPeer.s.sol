// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev On proxy OFTs, remove peer connection to legacy chains
// forge script scripts/UpgradeFrax/test/7b_DisconnectProxyPeer.s.sol --rpc-url https://rpc.frax.com
contract DisconnectProxyPeer is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    /// @dev skip deployment, disconnect proxy peer connections
    function run() public override {
        delete proxyOfts;
        // proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        // proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX
        proxyOfts.push(0x103C430c9Fcaa863EA90386e3d0d5cd53333876e); // Fraxtal CAC OFT

        // deploySource();
        // setupSource();
        setupDestinations();
    }

    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    /// @dev only set peers
    function setupDestination(
        L0Config memory /* _connectedConfig */,
        address[] memory _connectedOfts
    ) public /* simulateAndWriteTxs(_connectedConfig)*/ broadcastAs(configDeployerPK) {
        // setEvmEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: broadcastConfigArray
        // });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts, // overrides to address(0)
            // _configs: broadcastConfigArray 
            _configs: legacyConfigs
        });

        // setDVNs({
        //     _connectedConfig: _connectedConfig,
        //     _connectedOfts: _connectedOfts,
        //     _configs: broadcastConfigArray
        // });
    }

    /// @dev override peer address to address(0) and allow writing to active chain
    function setPeer(
        L0Config memory _config,
        address _connectedOft,
        bytes32 _peerOftAsBytes32
    ) public override {
        // cannot set peer to self
        if (block.chainid == _config.chainid) return;

        _peerOftAsBytes32 = addressToBytes32(address(0));

        bytes memory data = abi.encodeCall(
            IOAppCore.setPeer,
            (
                uint32(_config.eid), _peerOftAsBytes32
            )
        );
        (bool success, ) = _connectedOft.call(data);
        require(success, "Unable to setPeer");
        serializedTxs.push(
            SerializedTx({
                name: "setPeer",
                to: _connectedOft,
                value: 0,
                data: data
            })
        );
    }
}