// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Fixes missed peer set of sfrxUSD and frxUSD to sonic
// forge script scripts/ops/deploy/BatchDeploy/2b_FixOptimismPeers.s.sol --rpc-url https://rpc.soniclabs.com
contract FixOptimismPeers is DeployFraxOFTProtocol {
    
    using Strings for uint256;
    using stdJson for string;

    // adds "-fix" to maintain old file states
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, '/scripts/DeployFraxOFTProtocol/txs/');

        string memory name = string.concat("10-", simulateConfig.chainid.toString());
        name = string.concat(name, "-fix.json");
        return string.concat(root, name);
    }

    function run() public override {
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sfrxUSD
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUSD
        setupSource();
    }

    /// simulate as msig, only setup peers
    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        setupEvms();
    }

    function setupEvms() public override {
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });
    }


    // (s)frxUSD only to optimism
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        // require(frxUsdOft != address(0) && sfrxUsdOft != address(0), "ofts are null");
        
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                address peerOft = _peerOfts[o];
                // skip writing peer if not to ink
                if (_configs[c].chainid != 10) continue;

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(/*_peerOfts[o]*/ peerOft)
                });
            }
        }
    }

}