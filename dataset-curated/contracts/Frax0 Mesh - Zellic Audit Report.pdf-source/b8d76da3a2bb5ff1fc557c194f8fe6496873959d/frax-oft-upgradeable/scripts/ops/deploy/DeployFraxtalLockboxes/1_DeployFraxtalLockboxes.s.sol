// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {FraxOFTAdapterUpgradeable} from "contracts/FraxOFTAdapterUpgradeable.sol";

/// @dev deploys (s)frxETH/FXS/FPI lockboxes on fraxtal and wires them to proxy OFTs
// forge script scripts/ops/deploy/DeployFraxtalLockboxes/1_DeployFraxtalLockboxes.s.sol --rpc-url https://rpc.frax.com
contract DeployFraxtalLockboxes is DeployFraxOFTProtocol {
    using Strings for uint256;

    address wfrxEth = 0xFC00000000000000000000000000000000000006;
    address sfrxEth = 0xFC00000000000000000000000000000000000005;
    address fxs = 0xFc00000000000000000000000000000000000002;
    address fpi = 0xFc00000000000000000000000000000000000003;

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, '/scripts/ops/deploy/DeployFraxtalLockboxes/txs/');

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    function run() public override {
        // overwrite for setPeers
        frxUsdOft = address(1);
        sfrxUsdOft = address(1);

        delete expectedProxyOfts;
        expectedProxyOfts.push(proxyFrxEthOft);
        expectedProxyOfts.push(proxySFrxEthOft);
        expectedProxyOfts.push(proxyFraxOft);
        expectedProxyOfts.push(proxyFpiOft);

        deploySource();
        setupSource();
        setupDestinations();
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

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

    function setupDestination(
        L0Config memory _connectedConfig
    ) public override simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: expectedProxyOfts,
            _peerOfts: proxyOfts,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });

        setLibs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: expectedProxyOfts,
            _configs: broadcastConfigArray
        });
    }


    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts, // only frxUSD and sfrxUSD
            _peerOfts: expectedProxyOfts,
            _configs: proxyConfigs
        });
    }

    // skip verification of ofts as the addreses will be different
    function postDeployChecks() internal override pure {}

    // Deploy (s)frxETH/FXS/FPI
   function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        /// @dev already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;

        // deploy frxETH lockbox
        (fraxtalFrxEthLockbox, ) = deployFraxOFTUpgradeableAndProxy(wfrxEth);

        // deploy sfrxETH lockbox
        (fraxtalSFrxEthLockbox, ) = deployFraxOFTUpgradeableAndProxy(sfrxEth);

        // deploy fxs lockbox
        (fraxtalFraxLockbox, ) = deployFraxOFTUpgradeableAndProxy(fxs);

        // deploy fpi lockbox
        (fraxtalFpiLockbox, ) = deployFraxOFTUpgradeableAndProxy(fpi);
    }

    /// adds extra token addr to configure lockbox, uses adapter bytecode, init proxy to configDeployer as owner
    function deployFraxOFTUpgradeableAndProxy(
        address _token
    ) public returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTAdapterUpgradeable).creationCode),
            abi.encode(_token, broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(/* oftDeployerPK */ configDeployerPK), ""));

        /// @dev: broadcastConfig deployer is temporary OFT owner until setPriviledgedRoles()
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTAdapterUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        // Keep ownership as deployer
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);
        proxyOfts.push(proxy);

        // State checks
        // require(
        //     isStringEqual(FraxOFTUpgradeable(proxy).name(), _name),
        //     "OFT name incorrect"
        // );
        // require(
        //     isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol),
        //     "OFT symbol incorrect"
        // );
        require(
            address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }

    // skip proxy admin ownership transfer as it is already set up
    function setPriviledgedRoles() public override {
        /// @dev transfer ownership of OFT
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(broadcastConfig.delegate);
            Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        // Ownable(proxyAdmin).transferOwnership(broadcastConfig.delegate);
    }
}