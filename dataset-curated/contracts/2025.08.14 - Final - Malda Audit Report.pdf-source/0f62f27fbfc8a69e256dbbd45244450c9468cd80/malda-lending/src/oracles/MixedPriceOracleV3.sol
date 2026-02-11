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

contract MixedPriceOracleV3 is IOracleOperator {
    uint256 public immutable STALENESS_PERIOD;

    // ----------- STORAGE ------------
    mapping(string => IDefaultAdapter.PriceConfig) public configs;
    mapping(string => uint256) public stalenessPerSymbol;
    IRoles public immutable roles;

    error MixedPriceOracle_Unauthorized();
    error MixedPriceOracle_StalePrice();
    error MixedPriceOracle_InvalidPrice();
    error MixedPriceOracle_InvalidRound();
    error MixedPriceOracle_InvalidConfig();

    event ConfigSet(string symbol, IDefaultAdapter.PriceConfig config);
    event StalenessUpdated(string symbol, uint256 val);

    constructor(
        string[] memory symbols_,
        IDefaultAdapter.PriceConfig[] memory configs_,
        address roles_,
        uint256 stalenessPeriod_
    ) {
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

    function setConfig(string memory symbol, IDefaultAdapter.PriceConfig memory config) external {
        if (!roles.isAllowedFor(msg.sender, roles.GUARDIAN_ORACLE())) {
            revert MixedPriceOracle_Unauthorized();
        }
        if (config.defaultFeed == address(0)) {
            revert MixedPriceOracle_InvalidConfig();
        }
        configs[symbol] = config;
        emit ConfigSet(symbol, config);
    }

    function getPrice(address mToken) public view returns (uint256) {
        string memory symbol = ImTokenMinimal(mToken).symbol();
        return _getPriceUSD(symbol);
    }

    // price is extended for operator usage based on decimals of exchangeRate
    function getUnderlyingPrice(address mToken) external view override returns (uint256) {
        // ImTokenMinimal cast is needed for `.symbol()` call. No need to import a different interface
        string memory symbol = ImTokenMinimal(ImTokenMinimal(mToken).underlying()).symbol();
        IDefaultAdapter.PriceConfig memory config = configs[symbol];
        uint256 priceUsd = _getPriceUSD(symbol);
        return priceUsd * 10 ** (18 - config.underlyingDecimals);
    }

    function _getPriceUSD(string memory symbol) internal view returns (uint256) {
        IDefaultAdapter.PriceConfig memory config = configs[symbol];
        (uint256 feedPrice, uint256 feedDecimals) = _getLatestPrice(symbol, config);
        uint256 price = feedPrice * 10 ** (18 - feedDecimals);

        if (keccak256(abi.encodePacked(config.toSymbol)) != keccak256(abi.encodePacked("USD"))) {
            price = (price * _getPriceUSD(config.toSymbol)) / 10 ** 18;
        }

        return price;
    }

    function _getLatestPrice(string memory symbol, IDefaultAdapter.PriceConfig memory config)
        internal
        view
        returns (uint256, uint256)
    {
        if (config.defaultFeed == address(0)) revert("missing priceFeed");

        IDefaultAdapter feed = IDefaultAdapter(config.defaultFeed);

        // Get price and timestamp
        (,int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        require(price > 0, MixedPriceOracle_InvalidPrice());

        // Check for staleness
        require(block.timestamp - updatedAt < _getStaleness(symbol), MixedPriceOracle_StalePrice());

        uint256 decimals = feed.decimals();
        uint256 uPrice = uint256(price);

        return (uPrice, decimals);
    }

    function _getStaleness(string memory symbol) internal view returns (uint256) {
        uint256 _registered = stalenessPerSymbol[symbol];
        return _registered > 0 ? _registered : STALENESS_PERIOD;
    }
}
