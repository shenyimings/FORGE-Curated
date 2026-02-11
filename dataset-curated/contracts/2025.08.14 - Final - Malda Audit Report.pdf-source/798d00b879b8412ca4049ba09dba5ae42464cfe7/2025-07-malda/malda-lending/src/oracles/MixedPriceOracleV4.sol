// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {IRoles} from "src/interfaces/IRoles.sol";
import {ImTokenMinimal} from "src/interfaces/ImToken.sol";
import {IOracleOperator} from "src/interfaces/IOracleOperator.sol";
import {IDefaultAdapter} from "src/interfaces/IDefaultAdapter.sol";

contract MixedPriceOracleV4 is IOracleOperator {
    uint256 public immutable STALENESS_PERIOD;

    // ----------- STORAGE ------------
    struct PriceConfig {
        address api3Feed;
        address eOracleFeed;
        string toSymbol;
        uint256 underlyingDecimals;
    }

    mapping(string => PriceConfig) public configs;
    mapping(string => uint256) public stalenessPerSymbol;
    mapping(string => uint256) public deltaPerSymbol;

    uint256 public maxPriceDelta = 1.5e3; //1.5%
    uint256 public constant PRICE_DELTA_EXP = 1e5;
    IRoles public immutable roles;

    error MixedPriceOracle_Unauthorized();
    error MixedPriceOracle_ApiV3StalePrice();
    error MixedPriceOracle_eOracleStalePrice();
    error MixedPriceOracle_InvalidPrice();
    error MixedPriceOracle_InvalidRound();
    error MixedPriceOracle_InvalidConfig();
    error MixedPriceOracle_InvalidConfigDecimals();
    error MixedPriceOracle_DeltaTooHigh();
    error MixedPriceOracle_MissingFeed();

    event ConfigSet(string symbol, PriceConfig config);
    event StalenessUpdated(string symbol, uint256 val);
    event PriceDeltaUpdated(uint256 oldVal, uint256 newVal);
    event PriceSymbolDeltaUpdated(uint256 oldVal, uint256 newVal, string symbol);

    constructor(string[] memory symbols_, PriceConfig[] memory configs_, address roles_, uint256 stalenessPeriod_) {
        roles = IRoles(roles_);
        for (uint256 i = 0; i < symbols_.length; i++) {
            configs[symbols_[i]] = configs_[i];
        }
        STALENESS_PERIOD = stalenessPeriod_;
    }

    function setStaleness(string memory symbol, uint256 val) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_ORACLE())) {
            revert MixedPriceOracle_Unauthorized();
        }
        stalenessPerSymbol[symbol] = val;
        emit StalenessUpdated(symbol, val);
    }

    function setConfig(string memory symbol, PriceConfig memory config) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_ORACLE())) {
            revert MixedPriceOracle_Unauthorized();
        }
        if (config.api3Feed == address(0) || config.eOracleFeed == address(0)) {
            revert MixedPriceOracle_InvalidConfig();
        }

        configs[symbol] = config;
        emit ConfigSet(symbol, config);
    }

    function setMaxPriceDelta(uint256 _delta) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_ORACLE())) {
            revert MixedPriceOracle_Unauthorized();
        }

        require(_delta <= PRICE_DELTA_EXP, MixedPriceOracle_DeltaTooHigh());

        emit PriceDeltaUpdated(maxPriceDelta, _delta);
        maxPriceDelta = _delta;
    }

    function setSymbolMaxPriceDelta(uint256 _delta, string calldata _symbol) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_ORACLE())) {
            revert MixedPriceOracle_Unauthorized();
        }

        require(_delta <= PRICE_DELTA_EXP, MixedPriceOracle_DeltaTooHigh());

        emit PriceSymbolDeltaUpdated(deltaPerSymbol[_symbol], _delta, _symbol);
        deltaPerSymbol[_symbol] = _delta;
    }

    function getPrice(address mToken) public view returns (uint256) {
        string memory symbol = ImTokenMinimal(mToken).symbol();
        return _getPriceUSD(symbol);
    }

    // price is extended for operator usage based on decimals of exchangeRate
    function getUnderlyingPrice(address mToken) external view override returns (uint256) {
        // ImTokenMinimal cast is needed for `.symbol()` call. No need to import a different interface
        string memory symbol = ImTokenMinimal(ImTokenMinimal(mToken).underlying()).symbol();
        PriceConfig memory config = configs[symbol];
        uint256 priceUsd = _getPriceUSD(symbol);
        return priceUsd * 10 ** (18 - config.underlyingDecimals);
    }

    function _getPriceUSD(string memory symbol) internal view returns (uint256) {
        PriceConfig memory config = configs[symbol];
        (uint256 feedPrice, uint256 feedDecimals) = _getLatestPrice(symbol, config);
        uint256 price = feedPrice * 10 ** (18 - feedDecimals);

        if (keccak256(abi.encodePacked(config.toSymbol)) != keccak256(abi.encodePacked("USD"))) {
            price = (price * _getPriceUSD(config.toSymbol)) / 10 ** 18;
        }

        return price;
    }

    function _getLatestPrice(string memory symbol, PriceConfig memory config)
        internal
        view
        returns (uint256, uint256)
    {
        if (config.api3Feed == address(0) || config.eOracleFeed == address(0)) revert MixedPriceOracle_MissingFeed();

        //get both prices
        (, int256 apiV3Price,, uint256 apiV3UpdatedAt,) = IDefaultAdapter(config.api3Feed).latestRoundData();
        (, int256 eOraclePrice,, uint256 eOracleUpdatedAt,) = IDefaultAdapter(config.eOracleFeed).latestRoundData();

        // check if ApiV3 price is up to date
        uint256 _staleness = _getStaleness(symbol);
        bool apiV3Fresh = block.timestamp - apiV3UpdatedAt <= _staleness;

        // check delta
        uint256 delta = _absDiff(apiV3Price, eOraclePrice);
        uint256 deltaBps = (delta * PRICE_DELTA_EXP) / uint256(eOraclePrice < 0 ? -eOraclePrice : eOraclePrice);

        uint256 deltaSymbol = deltaPerSymbol[symbol];
        if (deltaSymbol == 0) {
            deltaSymbol = maxPriceDelta;
        }

        uint256 decimals;
        uint256 uPrice;
        if (!apiV3Fresh || deltaBps > deltaSymbol) {
            require(block.timestamp - eOracleUpdatedAt < _staleness, MixedPriceOracle_eOracleStalePrice());
            decimals = IDefaultAdapter(config.eOracleFeed).decimals();
            uPrice = uint256(eOraclePrice);
        } else {
            require(block.timestamp - apiV3UpdatedAt < _staleness, MixedPriceOracle_ApiV3StalePrice());
            decimals = IDefaultAdapter(config.api3Feed).decimals();
            uPrice = uint256(apiV3Price);
        }

        return (uPrice, decimals);
    }

    function _absDiff(int256 a, int256 b) internal pure returns (uint256) {
        return uint256(a >= b ? a - b : b - a);
    }

    function _getStaleness(string memory symbol) internal view returns (uint256) {
        uint256 _registered = stalenessPerSymbol[symbol];
        return _registered > 0 ? _registered : STALENESS_PERIOD;
    }
}
