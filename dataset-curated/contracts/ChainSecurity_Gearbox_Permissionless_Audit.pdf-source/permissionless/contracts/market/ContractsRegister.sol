// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ACLTrait} from "@gearbox-protocol/core-v3/contracts/traits/ACLTrait.sol";
import {SanityCheckTrait} from "@gearbox-protocol/core-v3/contracts/traits/SanityCheckTrait.sol";

import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {AP_CONTRACTS_REGISTER} from "../libraries/ContractLiterals.sol";

/// @title Contracts register
contract ContractsRegister is IContractsRegister, ACLTrait, SanityCheckTrait {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_CONTRACTS_REGISTER;

    /// @dev Set of registered pools
    EnumerableSet.AddressSet internal _registeredPoolsSet;

    /// @dev Set of shutdown pools
    EnumerableSet.AddressSet internal _shutdownPoolsSet;

    /// @dev Set of registered credit managers
    EnumerableSet.AddressSet internal _registeredCreditManagersSet;

    /// @dev Set of shutdown credit managers
    EnumerableSet.AddressSet internal _shutdownCreditManagersSet;

    /// @dev Mapping from registered pools to price oracles in respective markets
    mapping(address => address) internal _priceOracles;

    /// @dev Mapping from registered pools to loss policies in respective markets
    mapping(address => address) internal _lossPolicies;

    /// @notice Constructor
    /// @param acl_ ACL contract address
    constructor(address acl_) ACLTrait(acl_) {}

    // ------- //
    // MARKETS //
    // ------- //

    /// @notice Whether `pool` is one of registered pools
    function isPool(address pool) public view override returns (bool) {
        return _registeredPoolsSet.contains(pool);
    }

    /// @notice Returns the list of registered pools
    function getPools() external view override returns (address[] memory) {
        return _registeredPoolsSet.values();
    }

    /// @notice Returns the list of shutdown pools
    function getShutdownPools() external view override returns (address[] memory) {
        return _shutdownPoolsSet.values();
    }

    /// @notice Returns the price oracle of the market corresponding to `pool`
    /// @dev Reverts if `pool` is not registered
    function getPriceOracle(address pool) external view override returns (address) {
        if (!isPool(pool)) revert MarketNotRegisteredException(pool);
        return _priceOracles[pool];
    }

    /// @notice Returns the loss policy of the market corresponding to `pool`
    /// @dev Reverts if `pool` is not registered
    function getLossPolicy(address pool) external view override returns (address) {
        if (!isPool(pool)) revert MarketNotRegisteredException(pool);
        return _lossPolicies[pool];
    }

    /// @notice Registers the market corresponding to `pool`, sets `priceOracle` as its price oracle
    ///         and `lossPolicy` as its loss policy
    /// @dev Reverts if market was previously shutdown
    /// @dev Reverts if caller is not configurator
    /// @dev Reverts if any of `priceOracle` and `lossPolicy` is `address(0)`
    function registerMarket(address pool, address priceOracle, address lossPolicy)
        external
        override
        configuratorOnly
        nonZeroAddress(priceOracle)
        nonZeroAddress(lossPolicy)
    {
        if (!_registeredPoolsSet.add(pool)) return;
        if (_shutdownPoolsSet.contains(pool)) revert MarketShutDownException(pool);
        _priceOracles[pool] = priceOracle;
        _lossPolicies[pool] = lossPolicy;
        emit RegisterMarket(pool, priceOracle, lossPolicy);
    }

    /// @notice Shuts down the market corresponding to `pool`
    /// @dev Reverts if market is not registered
    /// @dev Reverts if market has registered credit suites
    /// @dev Reverts if caller is not configurator
    function shutdownMarket(address pool) external override configuratorOnly {
        if (!_shutdownPoolsSet.add(pool)) return;
        if (!_registeredPoolsSet.remove(pool)) revert MarketNotRegisteredException(pool);
        if (_getNumConnectedCreditManagers(pool, _registeredCreditManagersSet) != 0) {
            revert MarketNotEmptyException(pool);
        }
        _priceOracles[pool] = address(0);
        _lossPolicies[pool] = address(0);
        emit ShutdownMarket(pool);
    }

    /// @notice Sets `priceOracle` as price oracle of the market corresponding to `pool`
    /// @dev Reverts if market is not registered
    /// @dev Reverts if caller is not configurator
    /// @dev Reverts if `priceOracle` is `address(0)`
    function setPriceOracle(address pool, address priceOracle)
        external
        override
        configuratorOnly
        nonZeroAddress(priceOracle)
    {
        if (!isPool(pool)) revert MarketNotRegisteredException(pool);
        if (_priceOracles[pool] == priceOracle) return;
        _priceOracles[pool] = priceOracle;
        emit SetPriceOracle(pool, priceOracle);
    }

    /// @notice Sets `lossPolicy` as loss policy of the market corresponding to `pool`
    /// @dev Reverts if market is not registered
    /// @dev Reverts if caller is not configurator
    /// @dev Reverts if `lossPolicy` is `address(0)`
    function setLossPolicy(address pool, address lossPolicy)
        external
        override
        configuratorOnly
        nonZeroAddress(lossPolicy)
    {
        if (!isPool(pool)) revert MarketNotRegisteredException(pool);
        if (_lossPolicies[pool] == lossPolicy) return;
        _lossPolicies[pool] = lossPolicy;
        emit SetLossPolicy(pool, lossPolicy);
    }

    // ------------- //
    // CREDIT SUITES //
    // ------------- //

    /// @notice Whether `creditManager` is one of registered credit managers
    function isCreditManager(address creditManager) public view override returns (bool) {
        return _registeredCreditManagersSet.contains(creditManager);
    }

    /// @notice Returns the list of registered credit managers
    function getCreditManagers() external view override returns (address[] memory) {
        return _registeredCreditManagersSet.values();
    }

    /// @notice Returns the list of registered credit managers connected to `pool`
    /// @dev Reverts if `pool` is not registered
    function getCreditManagers(address pool) external view override returns (address[] memory) {
        if (!isPool(pool)) revert MarketNotRegisteredException(pool);
        return _getConnectedCreditManagers(pool, _registeredCreditManagersSet);
    }

    /// @notice Returns the list of shutdown credit managers
    function getShutdownCreditManagers() external view override returns (address[] memory) {
        return _shutdownCreditManagersSet.values();
    }

    /// @notice Returns the list of shutdown credit managers connected to `pool`
    /// @dev Reverts if `pool` is not registered unless it's already shutdown
    function getShutdownCreditManagers(address pool) external view override returns (address[] memory) {
        if (!isPool(pool) && !_shutdownPoolsSet.contains(pool)) revert MarketNotRegisteredException(pool);
        return _getConnectedCreditManagers(pool, _shutdownCreditManagersSet);
    }

    /// @notice Registers the credit suite corresponding to `creditManager`
    /// @dev Reverts if credit suite was previously shutdown
    /// @dev Reverts if `creditManager`'s market is not registered
    /// @dev Reverts if caller is not configurator
    function registerCreditSuite(address creditManager) external override configuratorOnly {
        if (!_registeredCreditManagersSet.add(creditManager)) return;
        if (_shutdownCreditManagersSet.contains(creditManager)) {
            revert CreditSuiteShutDownException(creditManager);
        }
        address pool = _pool(creditManager);
        if (!isPool(pool)) revert MarketNotRegisteredException(pool);
        emit RegisterCreditSuite(pool, creditManager);
    }

    /// @notice Shuts down the credit suite corresponding to `creditManager`
    /// @dev Reverts if credit suite is not registered
    /// @dev Reverts if caller is not configurator
    function shutdownCreditSuite(address creditManager) external override configuratorOnly {
        if (!_shutdownCreditManagersSet.add(creditManager)) return;
        if (!_registeredCreditManagersSet.remove(creditManager)) {
            revert CreditSuiteNotRegisteredException(creditManager);
        }
        emit ShutdownCreditSuite(_pool(creditManager), creditManager);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Returns the number of credit managers from `creditManagersSet` connected to `pool`
    function _getNumConnectedCreditManagers(address pool, EnumerableSet.AddressSet storage creditManagersSet)
        internal
        view
        returns (uint256 connected)
    {
        uint256 total = creditManagersSet.length();
        for (uint256 i; i < total; ++i) {
            if (_pool(creditManagersSet.at(i)) == pool) ++connected;
        }
    }

    /// @dev Returns the list of credit managers from `creditManagersSet` connected to `pool`
    function _getConnectedCreditManagers(address pool, EnumerableSet.AddressSet storage creditManagersSet)
        internal
        view
        returns (address[] memory creditManagers)
    {
        uint256 total = creditManagersSet.length();
        uint256 connected;
        creditManagers = new address[](total);
        for (uint256 i; i < total; ++i) {
            address creditManager = creditManagersSet.at(i);
            if (_pool(creditManager) == pool) creditManagers[connected++] = creditManager;
        }
        assembly {
            mstore(creditManagers, connected)
        }
    }

    /// @dev Returns the pool `creditManager` is connected to
    function _pool(address creditManager) internal view returns (address) {
        return ICreditManagerV3(creditManager).pool();
    }
}
