// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from "../interfaces/IMarketConfiguratorFactory.sol";
import {Call} from "../interfaces/Types.sol";

import {AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL} from "../libraries/ContractLiterals.sol";

import {DeployerTrait} from "../traits/DeployerTrait.sol";

abstract contract AbstractFactory is DeployerTrait, IFactory {
    address public immutable override marketConfiguratorFactory;

    modifier onlyMarketConfigurators() {
        _ensureCallerIsMarketConfigurator();
        _;
    }

    constructor(address addressProvider_) DeployerTrait(addressProvider_) {
        marketConfiguratorFactory = _getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function configure(address, bytes calldata callData) external virtual override returns (Call[] memory) {
        revert ForbiddenConfigurationCallException(bytes4(callData));
    }

    function emergencyConfigure(address, bytes calldata callData) external virtual override returns (Call[] memory) {
        revert ForbiddenEmergencyConfigurationCallException(bytes4(callData));
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _ensureCallerIsMarketConfigurator() internal view {
        if (!IMarketConfiguratorFactory(marketConfiguratorFactory).isMarketConfigurator(msg.sender)) {
            revert CallerIsNotMarketConfiguratorException(msg.sender);
        }
    }

    function _authorizeFactory(address marketConfigurator, address suite, address target)
        internal
        view
        returns (Call memory)
    {
        return Call({
            target: marketConfigurator,
            callData: abi.encodeCall(IMarketConfigurator.authorizeFactory, (address(this), suite, target))
        });
    }

    function _unauthorizeFactory(address marketConfigurator, address suite, address target)
        internal
        view
        returns (Call memory)
    {
        return Call({
            target: marketConfigurator,
            callData: abi.encodeCall(IMarketConfigurator.unauthorizeFactory, (address(this), suite, target))
        });
    }
}
