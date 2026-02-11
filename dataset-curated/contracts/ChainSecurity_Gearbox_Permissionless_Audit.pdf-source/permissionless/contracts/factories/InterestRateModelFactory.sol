// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IInterestRateModelFactory} from "../interfaces/factories/IInterestRateModelFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {Call, DeployParams, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {AP_INTEREST_RATE_MODEL_FACTORY, DOMAIN_IRM} from "../libraries/ContractLiterals.sol";

import {AbstractFactory} from "./AbstractFactory.sol";
import {AbstractMarketFactory} from "./AbstractMarketFactory.sol";

contract InterestRateModelFactory is AbstractMarketFactory, IInterestRateModelFactory {
    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_INTEREST_RATE_MODEL_FACTORY;

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) AbstractFactory(addressProvider_) {}

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployInterestRateModel(address pool, DeployParams calldata params)
        external
        override
        onlyMarketConfigurators
        returns (DeployResult memory)
    {
        if (params.postfix != "LINEAR") {
            _validateDefaultConstructorParams(pool, params.constructorParams);
        }

        address interestRateModel = _deployLatestPatch({
            contractType: _getContractType(DOMAIN_IRM, params.postfix),
            minorVersion: version,
            constructorParams: params.constructorParams,
            salt: keccak256(abi.encode(params.salt, msg.sender))
        });

        return DeployResult({
            newContract: interestRateModel,
            onInstallOps: CallBuilder.build(_authorizeFactory(msg.sender, pool, interestRateModel))
        });
    }

    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onUpdateInterestRateModel(address pool, address, address oldInterestRateModel)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        return CallBuilder.build(_unauthorizeFactory(msg.sender, pool, oldInterestRateModel));
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
        return CallBuilder.build(Call(_interestRateModel(pool), callData));
    }
}
