pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/DeprecateEthereumFXSLockbox/2_DeployEthereumWFRAX.s.sol --rpc-url https://ethereum-rpc.publicnode.com --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployEthereumWFRAX is DeployFraxOFTProtocol {
    using Strings for uint256;

    constructor() {
        // already deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        // get the _admin storage slot from the proxy
        // cast storage --rpc-url https://ethereum-rpc.publicnode.com 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/DeprecateEthereumFXSLockbox/txs/2_DeployEthereumWFRAX-");
        string memory name = string.concat(simulateConfig.chainid.toString(), ".json");
        return string.concat(root, name);
    }

    // override to maintain connectedOfts as configured in run()
    function _populateConnectedOfts() public override {}

    function postDeployChecks() internal override view {}

    L0Config[] public tempConfigs;
    function run() public override {
        delete connectedOfts;
        connectedOfts.push(fraxtalFraxLockbox);

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (
                proxyConfigs[i].chainid == 252 ||
                proxyConfigs[i].chainid == broadcastConfig.chainid
            ) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }
        require(tempConfigs.length == 2, "incorrect temp configs");

        delete proxyConfigs;
        for (uint256 i=0; i<tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        super.run();
    }

    function setupSource() public broadcastAs(configDeployerPK) override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: connectedOfts,
            _configs: proxyConfigs
        });

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

    /// @dev skip proxyAdmin transferOwnership as it's already set
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

    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "connectedOfts.length != _peerOfts.length");
        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {
                // address peerOft = determinePeer({
                //     _chainid: _configs[c].chainid,
                //     _oft: _peerOfts[o],
                //     _peerOfts: _peerOfts
                // });
                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(_peerOfts[o])
                });
            }
        }
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        // only deploy the WFRAX OFT
        (, wfraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Wrapped Frax",
            _symbol: "WFRAX"
        });
    }

    /// @dev override to set the owner of the proxy as configDeployerPK
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override returns (address implementation, address proxy) {
        implementation = address(new FraxOFTUpgradeable(broadcastConfig.endpoint)); 
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(configDeployerPK), ""));

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
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).name(), _name),
            "OFT name incorrect"
        );
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol),
            "OFT symbol incorrect"
        );
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
}