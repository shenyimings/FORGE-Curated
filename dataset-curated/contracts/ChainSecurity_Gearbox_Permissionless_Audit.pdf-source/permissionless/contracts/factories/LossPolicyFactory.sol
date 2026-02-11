// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {ILossPolicy} from "@gearbox-protocol/core-v3/contracts/interfaces/base/ILossPolicy.sol";

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {ILossPolicyFactory} from "../interfaces/factories/ILossPolicyFactory.sol";
import {Call, DeployParams, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {AP_LOSS_POLICY_FACTORY, DOMAIN_LOSS_POLICY} from "../libraries/ContractLiterals.sol";

import {AbstractFactory} from "./AbstractFactory.sol";
import {AbstractMarketFactory} from "./AbstractMarketFactory.sol";

contract LossPolicyFactory is AbstractMarketFactory, ILossPolicyFactory {
    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_LOSS_POLICY_FACTORY;

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) AbstractFactory(addressProvider_) {}

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployLossPolicy(address pool, DeployParams calldata params)
        external
        override
        onlyMarketConfigurators
        returns (DeployResult memory)
    {
        if (params.postfix == "ALIASED") {
            address decodedPool = abi.decode(params.constructorParams, (address));
            if (decodedPool != pool) revert InvalidConstructorParamsException();
        } else {
            _validateDefaultConstructorParams(pool, params.constructorParams);
        }

        address lossPolicy = _deployLatestPatch({
            contractType: _getContractType(DOMAIN_LOSS_POLICY, params.postfix),
            minorVersion: version,
            constructorParams: params.constructorParams,
            salt: keccak256(abi.encode(params.salt, msg.sender))
        });

        return DeployResult({
            newContract: lossPolicy,
            onInstallOps: CallBuilder.build(_authorizeFactory(msg.sender, pool, lossPolicy))
        });
    }

    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onUpdateLossPolicy(address pool, address, address oldLossPolicy)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory calls)
    {
        calls = CallBuilder.build(_unauthorizeFactory(msg.sender, pool, oldLossPolicy));
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function configure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        return CallBuilder.build(Call(_lossPolicy(pool), callData));
    }

    function emergencyConfigure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        bytes4 selector = bytes4(callData);
        if (selector != ILossPolicy.enable.selector && selector != ILossPolicy.disable.selector) {
            revert ForbiddenEmergencyConfigurationCallException(selector);
        }
        return CallBuilder.build(Call(_lossPolicy(pool), callData));
    }
}
