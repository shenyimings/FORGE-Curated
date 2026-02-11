// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { OFTUpgradeableMock } from "contracts/mocks/OFTUpgradeableMock.sol";

/// @dev deploy upgradeable mock OFTs and mint lockbox supply to the fraxtal msig
// forge script scripts/UpgradeFrax/test/2_DeployMockOFT.s.sol --rpc-url https://rpc.frax.com --broadcast --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY
contract DeployMockOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 initialCacSupply = 250_000e18;

    constructor() {
        // already deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
    }

    /// @dev override to only use FRAX, sFRAX as peer
    function setUp() public virtual override {
        loadJsonConfig();

        delete legacyOfts;
        legacyOfts.push(0xa536976c9cA36e74Af76037af555eefa632ce469); // CAC OFT on Base
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

    /// @dev skip base destination setup- do separate as configDeployer
    function setupDestinations() public pure override {
        require(address(0) == address(0));
    }

    /// @dev simple checks override
    function postDeployChecks() internal pure override {
        require(address(0) == address(0));
    }

    /// @dev only deploy the mock FRAX and sFRAX, as config deployer to maintain semi-deterministic-ness of the deployer nonce
    function deployFraxOFTUpgradeablesAndProxies() /* broadcastAs(oftDeployerPK) */ broadcastAs(configDeployerPK) public override {

        // deploy carter
        deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Carter",
            _symbol: "mCAC",
            _initialSupply: initialCacSupply
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
        OFTUpgradeableMock(proxy).mintInitialSupply(vm.addr(configDeployerPK), _initialSupply);

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