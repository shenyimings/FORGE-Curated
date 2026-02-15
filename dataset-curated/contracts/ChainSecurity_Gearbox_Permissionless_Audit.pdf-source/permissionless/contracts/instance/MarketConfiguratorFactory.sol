// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from "../interfaces/IMarketConfiguratorFactory.sol";

import {
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_MARKET_CONFIGURATOR,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_MARKET_CONFIGURATOR_LEGACY,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";

import {MarketConfiguratorLegacy} from "../market/legacy/MarketConfiguratorLegacy.sol";
import {MarketConfigurator} from "../market/MarketConfigurator.sol";

import {DeployerTrait} from "../traits/DeployerTrait.sol";

contract MarketConfiguratorFactory is DeployerTrait, IMarketConfiguratorFactory {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_MARKET_CONFIGURATOR_FACTORY;

    /// @dev Set of registered market configurators
    EnumerableSet.AddressSet internal _registeredMarketConfiguratorsSet;

    /// @dev Set of shutdown market configurators
    EnumerableSet.AddressSet internal _shutdownMarketConfiguratorsSet;

    /// @dev Reverts if caller is not cross-chain governance
    modifier onlyCrossChainGovernance() {
        if (msg.sender != _getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL)) {
            revert CallerIsNotCrossChainGovernanceException(msg.sender);
        }
        _;
    }

    /// @dev Reverts if caller is not one of market configurators
    modifier onlyMarketConfigurators() {
        if (!_registeredMarketConfiguratorsSet.contains(msg.sender)) {
            revert CallerIsNotMarketConfiguratorException(msg.sender);
        }
        _;
    }

    modifier onlyMarketConfiguratorAdmin(address marketConfigurator) {
        if (!_registeredMarketConfiguratorsSet.contains(marketConfigurator)) {
            revert AddressIsNotMarketConfiguratorException(marketConfigurator);
        }
        if (msg.sender != MarketConfigurator(marketConfigurator).admin()) {
            revert CallerIsNotMarketConfiguratorAdminException(msg.sender);
        }
        _;
    }

    constructor(address addressProvider_) DeployerTrait(addressProvider_) {}

    function isMarketConfigurator(address account) external view override returns (bool) {
        return _registeredMarketConfiguratorsSet.contains(account);
    }

    function getMarketConfigurators() external view override returns (address[] memory) {
        return _registeredMarketConfiguratorsSet.values();
    }

    function getMarketConfigurator(uint256 index) external view returns (address) {
        return _registeredMarketConfiguratorsSet.at(index);
    }

    function getNumMarketConfigurators() external view returns (uint256) {
        return _registeredMarketConfiguratorsSet.length();
    }

    function getShutdownMarketConfigurators() external view override returns (address[] memory) {
        return _shutdownMarketConfiguratorsSet.values();
    }

    function createMarketConfigurator(
        address admin,
        address emergencyAdmin,
        address adminFeeTreasury,
        string calldata curatorName,
        bool deployGovernor
    ) external override returns (address marketConfigurator) {
        marketConfigurator = _deployLatestPatch({
            contractType: AP_MARKET_CONFIGURATOR,
            minorVersion: 3_10,
            constructorParams: abi.encode(
                addressProvider, admin, emergencyAdmin, adminFeeTreasury, curatorName, deployGovernor
            ),
            salt: bytes32(bytes20(msg.sender))
        });

        _registeredMarketConfiguratorsSet.add(marketConfigurator);
        emit CreateMarketConfigurator(marketConfigurator, curatorName);
    }

    function shutdownMarketConfigurator(address marketConfigurator)
        external
        override
        onlyMarketConfiguratorAdmin(marketConfigurator)
    {
        if (_shutdownMarketConfiguratorsSet.add(marketConfigurator)) {
            revert MarketConfiguratorIsAlreadyShutdownException(marketConfigurator);
        }
        address contractsRegister = MarketConfigurator(marketConfigurator).contractsRegister();
        if (IContractsRegister(contractsRegister).getPools().length != 0) {
            revert CantShutdownMarketConfiguratorException();
        }
        _registeredMarketConfiguratorsSet.remove(marketConfigurator);
        emit ShutdownMarketConfigurator(marketConfigurator);
    }

    function addMarketConfigurator(address marketConfigurator) external override onlyCrossChainGovernance {
        if (_registeredMarketConfiguratorsSet.contains(marketConfigurator)) {
            revert MarketConfiguratorIsAlreadyAddedException(marketConfigurator);
        }
        if (_shutdownMarketConfiguratorsSet.contains(marketConfigurator)) {
            revert MarketConfiguratorIsAlreadyShutdownException(marketConfigurator);
        }
        _registeredMarketConfiguratorsSet.add(marketConfigurator);
        emit CreateMarketConfigurator(marketConfigurator, IMarketConfigurator(marketConfigurator).curatorName());
    }
}
