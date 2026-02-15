// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {BytecodeRepository} from "../global/BytecodeRepository.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    AP_INSTANCE_MANAGER,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_TREASURY,
    NO_VERSION_CONTROL,
    AP_BYTECODE_REPOSITORY,
    AP_ADDRESS_PROVIDER,
    AP_INSTANCE_MANAGER_PROXY,
    AP_CROSS_CHAIN_GOVERNANCE_PROXY,
    AP_TREASURY_PROXY,
    AP_GEAR_STAKING,
    AP_GEAR_TOKEN,
    AP_WETH_TOKEN,
    AP_MARKET_CONFIGURATOR_FACTORY
} from "../libraries/ContractLiterals.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IInstanceManager} from "../interfaces/IInstanceManager.sol";
import {ProxyCall} from "../helpers/ProxyCall.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {AddressProvider} from "./AddressProvider.sol";

contract InstanceManager is Ownable, IInstanceManager {
    using LibString for string;

    /// @notice Meta info about contract type & version
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_INSTANCE_MANAGER;

    address public immutable addressProvider;
    address public immutable bytecodeRepository;

    address public instanceManagerProxy;
    address public treasuryProxy;
    address public crossChainGovernanceProxy;

    bool public isActivated;

    error InvalidKeyException(string key);

    modifier onlyCrossChainGovernance() {
        require(
            msg.sender
                == IAddressProvider(addressProvider).getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL),
            "Only cross chain governance can call this function"
        );
        _;
    }

    modifier onlyTreasury() {
        require(
            msg.sender == IAddressProvider(addressProvider).getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL),
            "Only financial multisig can call this function"
        );
        _;
    }

    constructor(address _owner) {
        instanceManagerProxy = address(new ProxyCall());
        treasuryProxy = address(new ProxyCall());
        crossChainGovernanceProxy = address(new ProxyCall());

        bytecodeRepository = address(new BytecodeRepository(crossChainGovernanceProxy));
        addressProvider = address(new AddressProvider(address(this)));

        _setAddress(AP_BYTECODE_REPOSITORY, address(bytecodeRepository), false);
        _setAddress(AP_CROSS_CHAIN_GOVERNANCE, _owner, false);

        _setAddress(AP_INSTANCE_MANAGER_PROXY, instanceManagerProxy, false);
        _setAddress(AP_TREASURY_PROXY, treasuryProxy, false);
        _setAddress(AP_CROSS_CHAIN_GOVERNANCE_PROXY, crossChainGovernanceProxy, false);
        _setAddress(AP_INSTANCE_MANAGER, address(this), false);

        _transferOwnership(_owner);
    }

    function activate(address _instanceOwner, address _treasury, address _weth, address _gear) external onlyOwner {
        if (!isActivated) {
            _transferOwnership(_instanceOwner);

            _setAddress(AP_TREASURY, _treasury, false);
            _setAddress(AP_WETH_TOKEN, _weth, false);
            _setAddress(AP_GEAR_TOKEN, _gear, false);
            isActivated = true;
        }
    }

    function deploySystemContract(bytes32 _contractType, uint256 _version, bool _saveVersion)
        external
        onlyCrossChainGovernance
    {
        address newSystemContract;
        if (
            _contractType == AP_GEAR_STAKING && _version == 3_10
                && (block.chainid == 1 || block.chainid == 10 || block.chainid == 42161)
        ) {
            if (block.chainid == 1) {
                newSystemContract = 0x2fcbD02d5B1D52FC78d4c02890D7f4f47a459c33;
            } else if (block.chainid == 10) {
                newSystemContract = 0x8D2622f1CA3B42b637e2ff6753E6b69D3ab9Adfd;
            } else if (block.chainid == 42161) {
                newSystemContract = 0xf3599BEfe8E79169Afd5f0b7eb0A1aA322F193D9;
            }
        } else {
            newSystemContract = _deploySystemContract(_contractType, _version);
        }

        _setAddress(_contractType, newSystemContract, _saveVersion);
    }

    function _deploySystemContract(bytes32 _contractType, uint256 _version) internal returns (address) {
        try ProxyCall(crossChainGovernanceProxy).proxyCall(
            address(bytecodeRepository),
            abi.encodeCall(BytecodeRepository.deploy, (_contractType, _version, abi.encode(addressProvider), 0))
        ) returns (bytes memory result) {
            return abi.decode(result, (address));
        } catch {
            return address(0);
        }
    }

    function setGlobalAddress(string memory key, address addr, bool saveVersion) external onlyCrossChainGovernance {
        _setAddressWithPrefix(key, "GLOBAL_", addr, saveVersion);
    }

    function setLocalAddress(string memory key, address addr, bool saveVersion) external onlyOwner {
        _setAddressWithPrefix(key, "LOCAL_", addr, saveVersion);
    }

    function _setAddressWithPrefix(string memory key, string memory prefix, address addr, bool saveVersion) internal {
        if (!key.startsWith(prefix)) {
            revert InvalidKeyException(key);
        }
        IAddressProvider(addressProvider).setAddress(key, addr, saveVersion);
    }

    function configureGlobal(address target, bytes calldata data) external onlyCrossChainGovernance {
        _configureGlobal(target, data);
    }

    function _configureGlobal(address target, bytes memory data) internal {
        ProxyCall(crossChainGovernanceProxy).proxyCall(target, data);
    }

    function configureLocal(address target, bytes calldata data) external onlyOwner {
        ProxyCall(instanceManagerProxy).proxyCall(target, data);
    }

    function configureTreasury(address target, bytes calldata data) external onlyTreasury {
        ProxyCall(treasuryProxy).proxyCall(target, data);
    }

    function _setAddress(bytes32 key, address value, bool saveVersion) internal {
        IAddressProvider(addressProvider).setAddress(key, value, saveVersion);
    }
}
