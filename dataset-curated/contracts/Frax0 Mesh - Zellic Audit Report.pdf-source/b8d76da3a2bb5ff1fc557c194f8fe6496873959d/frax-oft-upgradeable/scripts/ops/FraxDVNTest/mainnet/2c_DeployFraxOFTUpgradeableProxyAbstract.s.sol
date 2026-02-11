// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTMintableUpgradeable.sol";
import { FraxOFTWalletUpgradeable } from "contracts/FraxOFTWalletUpgradeable.sol";

// abstract : forge script ./scripts/ops/FraxDVNTest/mainnet/2c_DeployFraxOFTUpgradeableProxy.s.sol --rpc-url https://api.mainnet.abs.xyz --zksync --verifier-url $ABSTRACT_ETHERSCAN_API_URL --etherscan-api-key $ABSTRACT_ETHERSCAN_API_KEY --verifier etherscan --verify --broadcast

contract DeployFraxOFTUpgradeableProxy is DeployFraxOFTProtocol {
    address[] public proxyOftWallets;
    address mFraxProxyAdmin = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;

    function run() public override {
        deploySource();
    }

    function postDeployChecks() internal view override {
        require(proxyOfts.length == 1, "Did not deploy OFT");
    }

    function deployFraxOFTUpgradeablesAndProxies() public override broadcastAs(oftDeployerPK) {
        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        implementationMock = 0x0AC30D5aAA765fb0BA5629C1e2BC9f7a0BBFfAe6;

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FRAX
        deployFraxOFTUpgradeableAndProxy({ _name: "Mock Frax", _symbol: "mFRAX" });
    }

    /// @notice Sourced from https://github.com/FraxFinance/LayerZero-v2-upgradeable/blob/e1470197e0cffe0d89dd9c776762c8fdcfc1e160/oapp/test/TestHelper.sol#L266
    ///     With state checks
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        proxyAdmin = mFraxProxyAdmin;

        implementation = 0xF0C2406A025f7b54322EF4D20EF6C9eCcece8402;
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
