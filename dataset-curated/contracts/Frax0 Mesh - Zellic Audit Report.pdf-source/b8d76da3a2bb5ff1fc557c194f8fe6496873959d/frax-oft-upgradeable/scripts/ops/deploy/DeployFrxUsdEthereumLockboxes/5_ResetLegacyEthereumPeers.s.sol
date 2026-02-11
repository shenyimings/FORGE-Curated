// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Reset the peers of legacy (s)FRAX eth lockboxes so that they cannot be bridged to proxy chains
// forge script scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/5_ResetLegacyEthereumPeers.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract ResetLegacyEthereumPeers is DeployFraxOFTProtocol {
    using Strings for uint256;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployFrxUsdEthereumLockboxes/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, "-reset-legacy-peers.json");
        return string.concat(root, name);
    }

    function run() public override {
        frxUsdOft = ethFrxUsdLockbox;
        sfrxUsdOft = ethSFrxUsdLockbox;

        delete expectedProxyOfts;
        expectedProxyOfts.push(address(0));
        expectedProxyOfts.push(address(0));

        delete ethLockboxes;
        ethLockboxes.push(ethFraxLockboxLegacy);
        ethLockboxes.push(ethSFraxLockboxLegacy);

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
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}