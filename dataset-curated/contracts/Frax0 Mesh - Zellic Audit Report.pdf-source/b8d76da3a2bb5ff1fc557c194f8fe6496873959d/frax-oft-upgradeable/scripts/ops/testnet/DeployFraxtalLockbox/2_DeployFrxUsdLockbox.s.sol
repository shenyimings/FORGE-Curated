// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTAdapterUpgradeable.sol";

/*
GOALS
- Deploy upgradeable frxUSD lockbox to Fraxtal testnet
    - Wire with LZ, Frax DVN
*/

/*
TODO
- determine peer oft address
- deploy adapter to frxusd
- wire correctly on source
- wire correctly on destination
*/

// forge script scripts/ops/testnet/DeployFraxtalLockbox/2_DeployFrxUsdLockbox.s.sol --rpc-url https://rpc.testnet.frax.com --broadcast
contract DeployFrxUsdLockbox is DeployFraxOFTProtocol {

    using Strings for uint256;
    using stdJson for string;

    address frxUsd = 0x452420df4AC1e3db5429b5FD629f3047482C543C; // frxUSD on Fraxtal testnet

    /// @notice broadcast instead of simulate
    modifier simulateAndWriteTxs(
        L0Config memory _simulateConfig
    ) override {
        simulateConfig = _simulateConfig;

        // Use the correct OFT addresses given the chain we're simulating
        _populateConnectedOfts();

        vm.createSelectFork(_simulateConfig.RPC);
        vm.startBroadcast(configDeployerPK);
        _;
        vm.stopBroadcast();
    }

    function preDeployChecks() public view override {}
    function postDeployChecks() internal view override {}

    function setupProxyDestinations() public override {
        // only setup testnet destinations
        for (uint256 i=0; i<testnetConfigs.length; i++) {
            if (testnetConfigs[i].eid == broadcastConfig.eid) continue;
            setupDestination({
                _connectedConfig: testnetConfigs[i]
            });
        }
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        setupEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: testnetConfigs
        });

        setLibs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: testnetConfigs
        });

        setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: testnetConfigs
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: proxyOfts,
            _configs: testnetConfigs
        });
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        proxyAdmin = vm.addr(senderDeployerPK);

        implementationMock = address(new ImplementationMock());
        
        (, frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _token: frxUsd
        });

        console.log("Deployed frxUSD Lockbox at:", frxUsdOft);
    }

    function deployFraxOFTUpgradeableAndProxy(address _token) public returns (address implementation, address proxy) {
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