// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev deploys to linea and only sets up destinations of Ethereum/Fraxtal lockboxes
// forge script scripts/ops/deploy/DeployLinea/DeployLinea.s.sol --rpc-url https://rpc.linea.build
contract DeployLinea is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployLinea/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function setupNonEvms() public override {}

    function setupProxyDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == broadcastConfig.eid) {
                continue;
            }
            // Set up destinations for Ethereum and Fraxtal lockboxes only
            if (proxyConfigs[i].chainid == 1 || proxyConfigs[i].chainid == 252) {
                setupDestination(proxyConfigs[i]);
            }
        }
    }

    function setPeer(
        L0Config memory _config,
        address _connectedOft,
        bytes32 _peerOftAsBytes32
    ) public override {
        // Only set peer if the config is linea, ethereum, or fraxtal
        if (_config.chainid != 59144 && _config.chainid != 1 && _config.chainid != 252) {
            return;
        }
        super.setPeer(_config, _connectedOft, _peerOftAsBytes32);
    }
}