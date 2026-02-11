// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
Update Sepolia <> Sepolia DVN stack to use Frax DVN
- Note: L0Config.dvnHorizon is used as an alias for frax DVN 
*/

// forge script scripts/ops/testnet/DeployFraxtalLockbox/3_UpgradeDVNStack.s.sol --rpc-url https://rpc.testnet.frax.com --broadcast
contract UpgradeDvnStack is DeployFraxOFTProtocol {

    function preDeployChecks() public view override {}
    function postDeployChecks() internal view override {}

    modifier broadcast(
        L0Config memory _config
    ) {
        simulateConfig = _config;

        _populateConnectedOfts();

        vm.createSelectFork(_config.RPC);
        vm.startBroadcast(configDeployerPK);
        _;
        vm.stopBroadcast();
    }

    function run() public override {
        proxyOfts.push(proxyFrxUsdOft);

        for (uint256 i=0; i<testnetConfigs.length; i++) {
            if (testnetConfigs[i].chainid == 2522) continue;

            setDVNs({
                _connectedConfig: testnetConfigs[i]
            });
        }
    }

    function setDVNs(
        L0Config memory _connectedConfig
    ) internal broadcast(_connectedConfig) {
        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: connectedOfts,
            _configs: testnetConfigs
        });
    }
}