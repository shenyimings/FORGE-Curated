// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMock } from "contracts/mocks/OFTUpgradeableMock.sol";

/// @dev deploy upgradeable mock OFTs and mint lockbox supply to the fraxtal msig
/*
forge script scripts/ops/UpgradeFrxUsd/2_DeployMockOFT.s.sol --rpc-url https://rpc.frax.com --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY --verify --broadcast
*/
contract DeployMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    // https://etherscan.io/token/0x853d955acef822db058eb8505911ed77f175b99e?a=0x909DBdE1eBE906Af95660033e478D59EFe831fED
    // minus
    // https://basescan.org/token/0x909DBdE1eBE906Af95660033e478D59EFe831fED
    uint256 initialFraxSupply = 816_384.457251e18 - 50.751238e18;

    // https://etherscan.io/token/0xa663b02cf0a4b149d2ad41910cb81e23e1c41c32?a=0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
    // minus
    // https://explorer.metis.io/token/0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
    // minus 
    // https://blastscan.io/token/0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
    // minus 
    // https://basescan.org/token/0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E
    uint256 initialSFraxSupply = 393_082.936436e18 - 102.14e18 - 28_129.82528e18 - 46_062.44659e18;

    constructor() {
        // already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
    }

    /// @dev override to only use FRAX, sFRAX as peer
    function setUp() public virtual override {
        loadJsonConfig();

        delete legacyOfts;
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/UpgradeFrxUsd/txs/");
        string memory name = string.concat("2_DeployMockOFT-", simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }

    /// @dev override to skip setting up solana, privileged roles
    function setupSource() public override broadcastAs(configDeployerPK) {
        /// @dev set enforced options / peers separately
        setupEvms();
        // setupNonEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        // setPriviledgedRoles();
    }

    // change setEvmPeers to point to legacy (aka Ethereum)
    // Can add other legacy peers w/o consequence as nothing will happen from an incorrect transfer
    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: /* proxyOfts */ legacyOfts,
            _configs: /* proxyConfigs */ legacyConfigs
        });
    }

    /// @dev only setup Ethereum destination
    function setupDestinations() public override {
        for (uint256 i=0; i<legacyConfigs.length; i++) {
            L0Config memory connectedConfig = legacyConfigs[i];
            if (connectedConfig.chainid == 1) {
                setupDestination({
                    _connectedConfig: connectedConfig,
                    _connectedOfts: legacyOfts
                });
            }
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public simulateAndWriteTxs(_connectedConfig) {
        setEvmEnforcedOptions({
            _connectedOfts: _connectedOfts,
            _configs: broadcastConfigArray
        });

        setEvmPeers({
            _connectedOfts: _connectedOfts,
            _peerOfts: proxyOfts,
            _configs: broadcastConfigArray 
        });

        setDVNs({
            _connectedConfig: _connectedConfig,
            _connectedOfts: _connectedOfts,
            _configs: broadcastConfigArray
        });
    }

    /// @dev simple checks override
    function postDeployChecks() internal override view {
        require(frxUsdOft != address(0));
        require(sfrxUsdOft != address(0));
    }

    /// @dev only deploy the mock FRAX and sFRAX, as config deployer to maintain semi-deterministic-ness of the deployer nonce
    function deployFraxOFTUpgradeablesAndProxies() /* broadcastAs(oftDeployerPK) */ broadcastAs(configDeployerPK) public override {

        // deploy frax
        (, frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax",
            _symbol: "mFRAX",
            _initialSupply: initialFraxSupply
        });

        // deploy sFrax
        (, sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Mock sFrax",
            _symbol: "msFrax",
            _initialSupply: initialSFraxSupply
        });
    }

    /// @dev override the bytecode to the mock contract and mint to the msig
   function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) public returns (address implementation, address proxy) {
        /// @dev override here
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(OFTUpgradeableMock).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }

        /// @dev override to configDeployerPK
        proxy = address(new TransparentUpgradeableProxy(implementationMock, /* vm.addr(oftDeployerPK) */ vm.addr(configDeployerPK), ""));

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

        /// @dev mint initial circulating supply
        OFTUpgradeableMock(proxy).mintInitialSupply(broadcastConfig.delegate, _initialSupply);

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

    /// @dev comment out the fraxtal override as we're pointing to the mock lockboxes
    function setEvmPeers(
        address[] memory _connectedOfts,
        address[] memory _peerOfts,
        L0Config[] memory _configs
    ) public override {
        require(_connectedOfts.length == _peerOfts.length, "Must wire equal amount of source + dest addrs");
        require(frxUsdOft != address(0) && sfrxUsdOft != address(0), "(s)frxUSD ofts are null");

        // For each OFT
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            address peerOft = _peerOfts[o];

            // Set the config per chain
            for (uint256 c=0; c<_configs.length; c++) {

                // // for fraxtal destination, override OFT address of (s)frxUSD to the standalone lockbox
                // if (_configs[c].chainid == 252) {
                //     if (_connectedOfts[o] == frxUsdOft) {
                //         // standalone frxUSD lockbox
                //         peerOft = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
                //     } else if (_connectedOfts[o] == sfrxUsdOft) {
                //         // standalone sfrxUSD lockbox
                //         peerOft = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
                //     }
                // } else {
                //     // Non-fraxtal destination: use the predeterministic address
                //     if (_connectedOfts[o] == frxUsdOft) {
                //         peerOft = frxUsdOft;
                //     } else if (_connectedOfts[o] == sfrxUsdOft) {
                //         peerOft = sfrxUsdOft;
                //     }
                // }

                setPeer({
                    _config: _configs[c],
                    _connectedOft: _connectedOfts[o],
                    _peerOftAsBytes32: addressToBytes32(peerOft)
                });
            }
        }
    }
}