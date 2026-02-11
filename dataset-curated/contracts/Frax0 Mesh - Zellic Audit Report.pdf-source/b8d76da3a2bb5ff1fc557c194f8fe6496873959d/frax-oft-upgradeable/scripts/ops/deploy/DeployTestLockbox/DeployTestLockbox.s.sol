// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTAdapterUpgradeable.sol";

// forge script scripts/ops/deploy/DeployTestLockbox/DeployTestLockbox.s.sol --rpc-url https://rpc.frax.com --broadcast --verify
contract DeployTestLockbox is DeployFraxOFTProtocol {

    address owner = 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A;
    address frxUsd = 0xFc00000000000000000000000000000000000001;

    function run() public override {
        deploySource();
        setupSource();
    }

    function postDeployChecks() internal override view {}

    // override setupSource to only set up options / solana
    function setupSource() public override broadcastAs(configDeployerPK) {
        setSolanaEnforcedOptions({
            _connectedOfts: proxyOfts
        });

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: nonEvmConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: nonEvmConfigs
        });
        setPriviledgedRoles();
    }

    function setPriviledgedRoles() public override {
        // set owner
        for (uint i = 0; i < proxyOfts.length; i++) {
            FraxOFTUpgradeable(proxyOfts[i]).setDelegate(owner);
            Ownable(proxyOfts[i]).transferOwnership(owner);
        }
    }


    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        (, frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _token: frxUsd
        });
    }

    function deployFraxOFTUpgradeableAndProxy(address _token) public returns (address implementation, address proxy) {
        proxyAdmin = owner;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        
        // create the implementation
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

        // TODO: shall we init implementation with address(0) ?
        // FraxOFTAdapterUpgradeable(implementation).initialize(address(0));

        // create the proxy
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(configDeployerPK), ""));
        proxyOfts.push(proxy);

        // upgrade and init
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTAdapterUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // transfer ownership to config deployer
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        require(
            FraxOFTAdapterUpgradeable(proxy).token() == _token,
            "OFT token not set"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }
}