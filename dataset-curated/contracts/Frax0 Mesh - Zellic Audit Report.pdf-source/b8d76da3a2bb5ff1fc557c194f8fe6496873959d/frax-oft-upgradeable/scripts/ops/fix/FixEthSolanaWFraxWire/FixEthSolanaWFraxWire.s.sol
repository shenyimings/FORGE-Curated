// SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/fix/FixEthSolanaWFraxWire/FixEthSolanaWFraxWire.s.sol --rpc-url https://eth-mainnet.public.blastapi.io
contract FixEthSolanaWFraxWire is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;


    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/fix/FixEthSolanaWFraxWire/");

        return string.concat(root, "FixEthSolanaWFraxWire.json");
    }

    function run() public override {
        setupSource();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        connectedOfts = new address[](1);
        connectedOfts[0] = ethFraxOft;

        // double check that we're dealing with solana config
        require(nonEvmConfigs[0].eid == 30168, "Not Solana config");
        L0Config[] memory solanaConfigAsArray = new L0Config[](1);
        solanaConfigAsArray[0] = nonEvmConfigs[0];

        /// @dev derived from DeployFraxOFTProtocol.setupNonEvms().
        setSolanaEnforcedOptions({
            _connectedOfts: connectedOfts
        });
        setPeer({
            _config: nonEvmConfigs[0],
            _connectedOft: ethFraxOft,
            _peerOftAsBytes32: 0x4939035f8dd13d15a9386e28b6705519aa6f488791323466a3c0116a201e51aa // from NonEvmPeers.json
        });

        /// @dev derived from DeployFraxOFTProtocol.setupSource().
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: connectedOfts,
            _configs: solanaConfigAsArray
        });
        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: connectedOfts,
            _configs: solanaConfigAsArray
        });

    }
}