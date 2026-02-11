// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTUpgradeable.sol";

// forge script scripts/ops/dvn/test/2_DeployTestOFT.s.sol --rpc-url https://arbitrum-sepolia.drpc.org --broadcast --verify

contract DeployTestOFT is DeployFraxOFTProtocol {
    address[] public connectedTestOfts;

    address owner = 0x009fF4940727C274424c16999F9632223d820b0b;
    address hardcodedProxyAdmin = 0xbF417B98Ef97Cc57FDD4b07c944A03dA4d7A565B;

    function run() public override {
        deploySource();
    }

    function preDeployChecks() public view override {
        for (uint256 e = 0; e < allConfigs.length; e++) {
            // skip if destination is not sepolia/arbsepolia
            if (allConfigs[e].eid != 40161 && allConfigs[e].eid != 40231) continue;
            uint256 eid = allConfigs[e].eid;
            // source and dest eid cannot be same
            if (eid == broadcastConfig.eid) continue;
            require(
                IMessageLibManager(broadcastConfig.endpoint).isSupportedEid(uint32(allConfigs[e].eid)),
                "L0 team required to setup `defaultSendLibrary` and `defaultReceiveLibrary` for EID"
            );
        }
    }

    function postDeployChecks() internal view override {
        require(proxyOfts.length == 1, "Did not deploy OFT");
    }

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = address(new ImplementationMock());

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d

        // Deploy frxUSD
        (, frxUsdOft) = deployFraxOFTUpgradeableAndProxy({ _name: "Frax USD", _symbol: "frxUSD" });
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        proxyAdmin = hardcodedProxyAdmin;

        implementation = address(new FraxOFTUpgradeable(broadcastConfig.endpoint));
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(oftDeployerPK), ""));
        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        proxyOfts.push(proxy);

        // State checks
        require(isStringEqual(FraxOFTUpgradeable(proxy).name(), _name), "OFT name incorrect");
        require(isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol), "OFT symbol incorrect");
        require(address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint, "OFT endpoint incorrect");
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK), "OFT owner incorrect");
    }
}
