// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {FraxOFTAdapterUpgradeable} from "contracts/FraxOFTAdapterUpgradeable.sol";

// Deploy fresh frxUSD, sfrxUSD lockboxes.
// forge script scripts/DeployInk/1_DeployFraxtalLockboxes.s.sol --rpc-url https://rpc.frax.com
contract DeployFraxtalLockboxes is DeployFraxOFTProtocol {

    address[] public inkProxyOfts;

    constructor() {
        inkProxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUsd
        inkProxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sfrxUsd
    }

    // customize setup to only set peers of the proxy frxUSD, sfrxUSD on ink
    function run() public override {
        deploySource();
        setupSource();
        // setupDestinations();
    }

    // skip solana
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

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: proxyOfts, // only frxUSD and sfrxUSD
            _peerOfts: /* proxyOfts */ inkProxyOfts,
            _configs: proxyConfigs
        });
    }

    // skip verification of ofts as the addreses will be different
    function postDeployChecks() internal override pure {}

    // deploy only frxUSD, sfrxUSD lockboxes
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        /// @dev already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;

        // deploy frxUSD
        (,frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _token: 0xFc00000000000000000000000000000000000001 // frxUsd
        });

        // deploy sfrxUSD
        (,sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _token: 0xfc00000000000000000000000000000000000008 // sfrxUsd
        });
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