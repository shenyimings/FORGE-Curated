// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
Notice:
Upon deployment it was found that Linea does not support Solidity v0.8.22.
Failed ProxyAdmin tx: https://lineascan.build/tx/0xc65e2672792430194d958b3ad338c08c25f5b5f85684b5c91f175e9d2df4dc42

So, we needed to redeploy the contracts with v0.8.22.

As the nonce increased from the failed tx, we need to skip deploying ProxyAdmin from the oftDeployerPK and deploy it manually
by the configDeployerPK.
*/

/// @dev deploys to linea and only sets up destinations of Ethereum/Fraxtal lockboxes
// forge script scripts/ops/deploy/DeployLinea/DeployLinea_2.s.sol --rpc-url https://rpc.linea.build
contract DeployLinea_2 is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployLinea/trax/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    // Additional deployment of proxyAdmin here
    function setupSource() public override broadcastAs(configDeployerPK) {
        proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));
        require(proxyAdmin == 0xa0E311912a0b0CF839Bc77dbdC2dE3c3e0846De4, "ProxyAdmin address incorrect");

        setupEvms();
        setupNonEvms();

        /// @dev configures legacy configs as well
        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        setPriviledgedRoles();
    }

    function setupNonEvms() public override {}

    // Skip setting up destinations as they were already set in the original DeployLinea.s.sol.
    // Simulating here will break when using evm_version = 'paris' in `foundry.toml`
    function setupProxyDestinations() public override {}

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

    /// @notice proxyAdmin commented out to maintain nonce order
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public override {

        // proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));
        proxyAdmin = 0xa0E311912a0b0CF839Bc77dbdC2dE3c3e0846De4;

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = address(new ImplementationMock());
        require(implementationMock == 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250, "Implementation mock address incorrect");

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FXS
        (,wfraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Share",
            _symbol: "FXS"
        });

        // Deploy sfrxUSD
        (,sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax USD",
            _symbol: "sfrxUSD"
        });

        // Deploy sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax Ether",
            _symbol: "sfrxETH"
        });

        // Deploy frxUSD
        (,frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax USD",
            _symbol: "frxUSD"
        });

        // Deploy frxETH
        (,frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Ether",
            _symbol: "frxETH"
        });

        // Deploy broken FPI
        deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Price Index",
            _symbol: "Mock FPI"
        });
        // pop off pushed proxy addr as it's the broken FPI
        proxyOfts.pop();

        // Deploy correct FPI
        (, fpiOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Price Index",
            _symbol: "FPI"
        });

        require(wfraxOft == proxyFraxOft, "wfraxOft address incorrect");
        require(sfrxUsdOft == proxySFrxUsdOft, "sfrxUsdOft address incorrect");
        require(sfrxEthOft == proxySFrxEthOft, "sfrxEthOft address incorrect");
        require(frxUsdOft == proxyFrxUsdOft, "frxUsdOft address incorrect");
        require(frxEthOft == proxyFrxEthOft, "frxEthOft address incorrect");
        require(fpiOft == proxyFpiOft, "fpiOft address incorrect");
    }
}