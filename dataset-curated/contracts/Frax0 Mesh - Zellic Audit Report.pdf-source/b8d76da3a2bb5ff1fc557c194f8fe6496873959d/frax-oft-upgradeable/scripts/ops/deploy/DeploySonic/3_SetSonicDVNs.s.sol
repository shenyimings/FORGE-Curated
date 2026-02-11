pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// Configure the Sonic DVNs to Horizen and LZ now that Horizen DVN is live
// forge script scripts/ops/deploy/DeploySonic/3_SetSonicDVNs.s.sol --rpc-url https://rpc.soniclabs.com
contract SetSonicDVNs is DeployFraxOFTProtocol {
    using Strings for uint256;

    // overwrite to put msig tx in local dir
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeploySonic/txs/");
        string memory name = string.concat(broadcastConfig.chainid.toString(), ".json");
        return string.concat(root, name);
    }

    // set DVNs
    function run() public override {
        // deploySource();
        
        // since ofts are already deployed, manually populate the addresses for setup
        proxyOfts.push(expectedProxyOfts[0]);
        proxyOfts.push(expectedProxyOfts[1]);
        proxyOfts.push(expectedProxyOfts[2]);
        proxyOfts.push(expectedProxyOfts[3]);
        proxyOfts.push(expectedProxyOfts[4]);
        proxyOfts.push(expectedProxyOfts[5]);

        setupSource();
        // setupDestinations();
    }

    // only set DVNs, simulate as msig
    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });
    }
}