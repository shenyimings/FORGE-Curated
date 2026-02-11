// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IRateKeeper} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IRateKeeper.sol";
import {IGaugeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IGaugeV3.sol";

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {IRateKeeperFactory} from "../interfaces/factories/IRateKeeperFactory.sol";
import {Call, DeployParams, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {
    DOMAIN_RATE_KEEPER,
    AP_RATE_KEEPER_FACTORY,
    NO_VERSION_CONTROL,
    AP_GEAR_STAKING
} from "../libraries/ContractLiterals.sol";

import {AbstractFactory} from "./AbstractFactory.sol";
import {AbstractMarketFactory} from "./AbstractMarketFactory.sol";

contract RateKeeperFactory is AbstractMarketFactory, IRateKeeperFactory {
    using CallBuilder for Call[];

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_RATE_KEEPER_FACTORY;

    /// @notice Address of the GEAR staking contract
    address public immutable gearStaking;

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) AbstractFactory(addressProvider_) {
        gearStaking = _getAddressOrRevert(AP_GEAR_STAKING, NO_VERSION_CONTROL);
    }

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployRateKeeper(address pool, DeployParams calldata params)
        external
        override
        onlyMarketConfigurators
        returns (DeployResult memory)
    {
        if (params.postfix == "GAUGE") {
            (address decodedPool, address decodedGearStaking) = abi.decode(params.constructorParams, (address, address));
            if (decodedPool != pool || decodedGearStaking != gearStaking) revert InvalidConstructorParamsException();
        } else if (params.postfix == "TUMBLER") {
            (address decodedPool,) = abi.decode(params.constructorParams, (address, uint256));
            if (decodedPool != pool) revert InvalidConstructorParamsException();
        } else {
            _validateDefaultConstructorParams(pool, params.constructorParams);
        }

        address rateKeeper = _deployLatestPatch({
            contractType: _getContractType(DOMAIN_RATE_KEEPER, params.postfix),
            minorVersion: version,
            constructorParams: params.constructorParams,
            salt: keccak256(abi.encode(params.salt, msg.sender))
        });

        return DeployResult({
            newContract: rateKeeper,
            onInstallOps: CallBuilder.build(_authorizeFactory(msg.sender, pool, rateKeeper))
        });
    }

    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onCreateMarket(address, address, address, address rateKeeper, address, address)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        if (_getRateKeeperType(rateKeeper) == "RATE_KEEPER::GAUGE") {
            return CallBuilder.build(_setFrozenEpoch(rateKeeper, false));
        }
        return CallBuilder.build();
    }

    function onShutdownMarket(address pool)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        address rateKeeper = _rateKeeper(_quotaKeeper(pool));
        if (_getRateKeeperType(rateKeeper) == "RATE_KEEPER::GAUGE") {
            return CallBuilder.build(_setFrozenEpoch(rateKeeper, true));
        }
        return CallBuilder.build();
    }

    function onUpdateRateKeeper(address pool, address newRateKeeper, address oldRateKeeper)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory calls)
    {
        address[] memory tokens = _quotedTokens(_quotaKeeper(pool));
        uint256 numTokens = tokens.length;
        calls = new Call[](numTokens);
        bytes32 type_ = _getRateKeeperType(newRateKeeper);
        for (uint256 i; i < numTokens; ++i) {
            calls[i] = _addToken(newRateKeeper, tokens[i], type_);
        }
        if (_getRateKeeperType(oldRateKeeper) == "RATE_KEEPER::GAUGE") {
            calls = calls.append(_setFrozenEpoch(oldRateKeeper, true));
        }
        if (type_ == "RATE_KEEPER::GAUGE") {
            calls = calls.append(_setFrozenEpoch(oldRateKeeper, false));
        }
        calls = calls.append(_unauthorizeFactory(msg.sender, pool, oldRateKeeper));
    }

    function onAddToken(address pool, address token, address)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        address rateKeeper = _rateKeeper(_quotaKeeper(pool));
        return CallBuilder.build(_addToken(rateKeeper, token, _getRateKeeperType(rateKeeper)));
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
        address rateKeeper = _rateKeeper(_quotaKeeper(pool));
        bytes4 selector = bytes4(callData);
        if (_isForbiddenConfigurationCall(rateKeeper, selector)) revert ForbiddenConfigurationCallException(selector);
        return CallBuilder.build(Call(rateKeeper, callData));
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _getRateKeeperType(address rateKeeper) internal view returns (bytes32) {
        try IRateKeeper(rateKeeper).contractType() returns (bytes32 type_) {
            return type_;
        } catch {
            return "RATE_KEEPER::GAUGE";
        }
    }

    function _isForbiddenConfigurationCall(address rateKeeper, bytes4 selector) internal view returns (bool) {
        if (_getRateKeeperType(rateKeeper) == "RATE_KEEPER::GAUGE") {
            return selector == IRateKeeper.addToken.selector || selector == IGaugeV3.addQuotaToken.selector
                || selector == IGaugeV3.setFrozenEpoch.selector || selector == bytes4(keccak256("setController(address)"));
        }
        return selector == IRateKeeper.addToken.selector;
    }

    function _addToken(address rateKeeper, address token, bytes32 type_) internal pure returns (Call memory) {
        return Call(
            rateKeeper,
            type_ == "RATE_KEEPER::GAUGE"
                ? abi.encodeCall(IGaugeV3.addQuotaToken, (token, 1, 1))
                : abi.encodeCall(IRateKeeper.addToken, token)
        );
    }

    function _setFrozenEpoch(address gauge, bool status) internal pure returns (Call memory) {
        return Call(gauge, abi.encodeCall(IGaugeV3.setFrozenEpoch, status));
    }
}
