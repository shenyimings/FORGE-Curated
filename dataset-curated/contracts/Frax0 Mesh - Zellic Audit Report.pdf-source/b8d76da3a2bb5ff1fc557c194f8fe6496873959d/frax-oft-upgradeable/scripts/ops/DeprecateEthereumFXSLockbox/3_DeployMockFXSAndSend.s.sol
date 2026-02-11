// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMockMint } from "contracts/mocks/OFTUpgradeableMockMint.sol";
import { FXSCustodianMock } from "contracts/mocks/FXSCustodianMock.sol";

/*
1. Deploy the mock FXS custodian
2. Deploy the mock FXS OFT
    - Wire to ethereum lockbox
3. Init the custodian
4. Submit Ethereum tx to connect the peer to the mock FXS OFT
5. Build the send txs to submit to the msig
    a. Execute initialSend()
    b. Execute fullSend()
*/

// forge script scripts/ops/DeprecateEthereumFXSLockbox/3_DeployMockFXSAndSend.s.sol --rpc-url https://rpc.frax.com --broadcast --verify --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY
contract DeployMockFXSAndSend is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    L0Config public ethConfig;
    FXSCustodianMock public custodian;
    uint256 public fraxtalTxCnt;

    uint256 initialFxsLockboxBalance = 244293293609000000000000;

    constructor() {
        // already deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        // doesn't matter what address the proxyAdmin is- just needs to be non-zero for `deployFraxOFTUpgradeableAndProxy()`
        proxyAdmin = address(0x11);
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/DeprecateEthereumFXSLockbox/txs/3_DeployMockFXSAndSend-");

        string memory file;
        if (simulateConfig.chainid == 252) {
            if (fraxtalTxCnt == 1) {
                file = string.concat(simulateConfig.chainid.toString(), "-initialSend.json");
            } else {
                file = string.concat(simulateConfig.chainid.toString(), "-fullSend.json");
            }
        } else {
            file = string.concat(simulateConfig.chainid.toString(), ".json");
        }

        return string.concat(root, file);
    }

    function run() public override {
        delete connectedOfts;
        connectedOfts.push(ethFraxLockbox);

        for (uint256 i=0; i<proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 1) {
                ethConfig = proxyConfigs[i];
            }
        }
        require(ethConfig.chainid == 1, "Ethereum config not found");
        delete proxyConfigs;
        proxyConfigs.push(ethConfig);
        require(proxyConfigs.length == 1, "Only Eth dest config should be set");

        deploySource();
        setupSource();
        buildCustodianInitialSendTx();
        buildCustodianFullSendTx();
        setupDestinations();
    }

    function buildCustodianInitialSendTx() public simulateAndWriteTxs(broadcastConfig) {
        uint256 value = 10e18;
        bytes memory data = abi.encodeWithSelector(FXSCustodianMock.initialSend.selector);
        (bool success, ) = address(custodian).call{value: value}(data);
        require(success, "FXSCustodianMock.initialSend failed");
        serializedTxs.push(
            SerializedTx({
                name: "FXSCustodianMock.initialSend",
                to: address(custodian),
                value: value,
                data: data
            })
        );

        fraxtalTxCnt++;
    }

    function buildCustodianFullSendTx() public simulateAndWriteTxs(broadcastConfig) {
        bytes memory data = abi.encodeWithSelector(FXSCustodianMock.fullSend.selector);
        (bool success, ) = address(custodian).call(data);
        require(success, "FXSCustodianMock.fullSend failed");
        serializedTxs.push(
            SerializedTx({
                name: "FXSCustodianMock.fullSend",
                to: address(custodian),
                value: 0,
                data: data
            })
        );

        fraxtalTxCnt++;
    }

    function deploySource() public override {
        deployCustodian();
        deployFraxOFTUpgradeablesAndProxies();
        initCustodian();
    }

    function initCustodian() public broadcastAs(configDeployerPK) {
        custodian.initialize({
            _mockFxsOft: wfraxOft,
            _initialOwner: broadcastConfig.delegate
        });
    }

    // override to maintain connectedOfts as configured in run()
    function _populateConnectedOfts() public override {}

    function setupSource() public override broadcastAs(configDeployerPK) {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: connectedOfts,
            _configs: proxyConfigs
        });

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

/// @notice skip proxyAdmin ownership transfer
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

    // Deploy the mock FXS
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        (, wfraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax",
            _symbol: "mFRAX",
            _initialSupply: initialFxsLockboxBalance
        });
    }

    function deployCustodian() public broadcastAs(configDeployerPK) {
        custodian = new FXSCustodianMock();
        console.log("custodian deployed at: ", address(custodian));
    }

    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) public returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(OFTUpgradeableMockMint).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(configDeployerPK), ""));

        bytes memory initializeArgs = abi.encodeWithSelector(
            OFTUpgradeableMockMint.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK),
            _initialSupply,
            address(custodian)
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