// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/MoveLegacyLiquidity/2_DisconnectEthereumToFraxtal.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract DisconnectEthereumToFraxtal is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;

    L0Config public fraxtalConfig;


    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/scripts/ops/MoveLegacyLiquidity/txs/2_DisconnectEthereumToFraxtal.json");
    }

    function _populateConnectedOfts() public override {}

    function run() public override simulateAndWriteTxs(broadcastConfig) {
        // set fraxtal config
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 252) {
                fraxtalConfig = proxyConfigs[i];
            }
        }

        for (uint256 i=0; i<ethLockboxesLegacy.length; i++) {
            address lockbox = ethLockboxesLegacy[i];
            setPeer({
                _config: fraxtalConfig,
                _connectedOft: lockbox,
                _peerOftAsBytes32: bytes32(0)
            });
        }
    }
}
