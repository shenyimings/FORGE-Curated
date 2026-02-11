// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IPriceFeed, IUpdatablePriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {IPriceOracleFactory} from "../interfaces/factories/IPriceOracleFactory.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {IPriceFeedStore} from "../interfaces/IPriceFeedStore.sol";
import {Call, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {
    AP_PRICE_FEED_STORE,
    AP_PRICE_ORACLE,
    AP_PRICE_ORACLE_FACTORY,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";
import {NestedPriceFeeds} from "../libraries/NestedPriceFeeds.sol";

import {AbstractFactory} from "./AbstractFactory.sol";
import {AbstractMarketFactory} from "./AbstractMarketFactory.sol";

interface IConfigureActions {
    function setPriceFeed(address token, address priceFeed) external;
    function setReservePriceFeed(address token, address priceFeed) external;
}

interface IEmergencyConfigureActions {
    function setPriceFeed(address token, address priceFeed) external;
}

contract PriceOracleFactory is AbstractMarketFactory, IPriceOracleFactory {
    using CallBuilder for Call[];
    using NestedPriceFeeds for IPriceFeed;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_PRICE_ORACLE_FACTORY;

    /// @notice Address of the price feed store contract
    address public immutable priceFeedStore;

    /// @notice Thrown when trying to set price feed for a token that is not allowed in the price feed store
    error PriceFeedNotAllowedException(address token, address priceFeed);

    /// @notice Thrown when trying to set a price feed that was allowed too recently
    error PriceFeedAllowedTooRecentlyException(address token, address priceFeed);

    /// @notice Thrown when trying to set price feed for a token that has not been added to the market
    error TokenIsNotAddedException(address token);

    /// @notice Thrown when trying to set zero price feed for pool's underlying or a token with non-zero quota
    error ZeroPriceFeedException(address token);

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) AbstractFactory(addressProvider_) {
        priceFeedStore = _getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL);
    }

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployPriceOracle(address pool) external override onlyMarketConfigurators returns (DeployResult memory) {
        address acl = IMarketConfigurator(msg.sender).acl();

        address priceOracle = _deployLatestPatch({
            contractType: AP_PRICE_ORACLE,
            minorVersion: version,
            constructorParams: abi.encode(acl),
            salt: bytes32(bytes20(pool))
        });

        return DeployResult({
            newContract: priceOracle,
            onInstallOps: CallBuilder.build(_authorizeFactory(msg.sender, pool, priceOracle))
        });
    }

    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onCreateMarket(address pool, address priceOracle, address, address, address, address underlyingPriceFeed)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        address underlying = _underlying(pool);
        _revertOnZeroPriceFeed(underlying, underlyingPriceFeed);
        return _setPriceFeed(priceOracle, underlying, underlyingPriceFeed, false);
    }

    function onUpdatePriceOracle(address pool, address newPriceOracle, address oldPriceOracle)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory calls)
    {
        calls = CallBuilder.build(_unauthorizeFactory(msg.sender, pool, oldPriceOracle));

        address underlying = _underlying(pool);
        calls = calls.extend(
            _setPriceFeed(newPriceOracle, underlying, _getPriceFeed(oldPriceOracle, underlying, false), false)
        );

        address[] memory tokens = _quotedTokens(_quotaKeeper(pool));
        uint256 numTokens = tokens.length;
        for (uint256 i; i < numTokens; ++i) {
            address main = _getPriceFeed(oldPriceOracle, tokens[i], false);
            calls = calls.extend(_setPriceFeed(newPriceOracle, tokens[i], main, false));

            address reserve = _getPriceFeed(oldPriceOracle, tokens[i], true);
            if (reserve != address(0)) calls = calls.extend(_setPriceFeed(newPriceOracle, tokens[i], reserve, true));
        }
    }

    function onAddToken(address pool, address token, address priceFeed)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        return _setPriceFeed(_priceOracle(pool), token, priceFeed, false);
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
        address priceOracle = _priceOracle(pool);

        bytes4 selector = bytes4(callData);
        if (selector == IConfigureActions.setPriceFeed.selector) {
            (address token, address priceFeed) = abi.decode(callData[4:], (address, address));
            _validatePriceFeed(pool, token, priceFeed, true);
            return _setPriceFeed(priceOracle, token, priceFeed, false);
        } else if (selector == IConfigureActions.setReservePriceFeed.selector) {
            (address token, address priceFeed) = abi.decode(callData[4:], (address, address));
            _validatePriceFeed(pool, token, priceFeed, false);
            return _setPriceFeed(priceOracle, token, priceFeed, true);
        } else {
            revert ForbiddenConfigurationCallException(selector);
        }
    }

    function emergencyConfigure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        address priceOracle = _priceOracle(pool);

        bytes4 selector = bytes4(callData);
        if (selector == IConfigureActions.setPriceFeed.selector) {
            (address token, address priceFeed) = abi.decode(callData[4:], (address, address));
            _validatePriceFeed(pool, token, priceFeed, true);
            if (block.timestamp < IPriceFeedStore(priceFeedStore).getAllowanceTimestamp(token, priceFeed) + 1 days) {
                revert PriceFeedAllowedTooRecentlyException(token, priceFeed);
            }
            return _setPriceFeed(priceOracle, token, priceFeed, false);
        } else {
            revert ForbiddenEmergencyConfigurationCallException(selector);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _validatePriceFeed(address pool, address token, address priceFeed, bool revertOnZeroPrice) internal view {
        address underlying = _underlying(pool);
        address quotaKeeper = _quotaKeeper(pool);
        if (token != underlying && !_isQuotedToken(quotaKeeper, token)) {
            revert TokenIsNotAddedException(token);
        }
        if (revertOnZeroPrice && (token == underlying || _quota(quotaKeeper, token) != 0)) {
            _revertOnZeroPriceFeed(token, priceFeed);
        }
    }

    function _revertOnZeroPriceFeed(address token, address priceFeed) internal view {
        (, int256 answer,,,) = IPriceFeed(priceFeed).latestRoundData();
        if (answer == 0) revert ZeroPriceFeedException(token);
    }

    function _getPriceFeed(address priceOracle, address token, bool reserve) internal view returns (address) {
        return reserve
            ? IPriceOracleV3(priceOracle).reservePriceFeeds(token)
            : IPriceOracleV3(priceOracle).priceFeeds(token);
    }

    function _setPriceFeed(address priceOracle, address token, address priceFeed, bool reserve)
        internal
        view
        returns (Call[] memory)
    {
        if (!IPriceFeedStore(priceFeedStore).isAllowedPriceFeed(token, priceFeed)) {
            revert PriceFeedNotAllowedException(token, priceFeed);
        }
        uint32 stalenessPeriod = IPriceFeedStore(priceFeedStore).getStalenessPeriod(priceFeed);

        Call[] memory calls = CallBuilder.build(
            reserve
                ? _setReservePriceFeed(priceOracle, token, priceFeed, stalenessPeriod)
                : _setPriceFeed(priceOracle, token, priceFeed, stalenessPeriod)
        );
        return _addUpdatableFeeds(priceOracle, priceFeed, calls);
    }

    function _addUpdatableFeeds(address priceOracle, address priceFeed, Call[] memory calls)
        internal
        view
        returns (Call[] memory)
    {
        try IUpdatablePriceFeed(priceFeed).updatable() returns (bool updatable) {
            if (updatable) calls = calls.append(_addUpdatablePriceFeed(priceOracle, priceFeed));
        } catch {}
        address[] memory underlyingFeeds = IPriceFeed(priceFeed).getUnderlyingFeeds();
        uint256 numFeeds = underlyingFeeds.length;
        for (uint256 i; i < numFeeds; ++i) {
            calls = _addUpdatableFeeds(priceOracle, underlyingFeeds[i], calls);
        }
        return calls;
    }

    function _setPriceFeed(address priceOracle, address token, address priceFeed, uint32 stalenessPeriod)
        internal
        pure
        returns (Call memory)
    {
        return Call(priceOracle, abi.encodeCall(IPriceOracleV3.setPriceFeed, (token, priceFeed, stalenessPeriod)));
    }

    function _setReservePriceFeed(address priceOracle, address token, address priceFeed, uint32 stalenessPeriod)
        internal
        pure
        returns (Call memory)
    {
        return
            Call(priceOracle, abi.encodeCall(IPriceOracleV3.setReservePriceFeed, (token, priceFeed, stalenessPeriod)));
    }

    function _addUpdatablePriceFeed(address priceOracle, address priceFeed) internal pure returns (Call memory) {
        return Call(priceOracle, abi.encodeCall(IPriceOracleV3.addUpdatablePriceFeed, (priceFeed)));
    }
}
