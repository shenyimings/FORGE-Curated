// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import "scripts/ops/deploy/DeployRandomAddressOFTs/DeployRandomAddressOFTs.s.sol";
/*
Notice:
DeployLinea_2 stopped deployment @ https://lineascan.build/tx/0x20d5879a092947091e9e8ba05e90818e500d22eb4328179af741ee59ad40a622
due to lack of funds.

I then messed up the nonce of the config deployer by transferring funds to the deployer.

So the proxyAdmin address which is to be set in the DeployLinea_2.s.sol script is no longer able to exist as 
the nonce is now higher.

Therefore, I need to deploy the contracts from scratch from the config and have different addresses


*/

// forge script scripts/ops/deploy/DeployLinea/DeployLinea_3.s.sol --rpc-url https://rpc.linea.build
contract DeployLinea_3 is DeployRandomAddressOFTs {
    using Strings for uint256;
    using stdJson for string;

    L0Config[] public tempConfigs;

    function run() public override {
        // make proxyOfts only Linea, Ethereum, and Fraxtal
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // Set up destinations for Ethereum and Fraxtal lockboxes only
            if (
                proxyConfigs[i].chainid == 1 ||
                proxyConfigs[i].chainid == 252 ||
                proxyConfigs[i].chainid == broadcastConfig.chainid
            ) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        delete proxyConfigs;
        for (uint256 i=0; i<tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        super.run();
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployLinea/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    function setupNonEvms() public override {}

    function setupProxyDestinations() public override {}
}