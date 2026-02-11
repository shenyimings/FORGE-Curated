// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {BaseParams} from "./BaseState.sol";

/// @notice Price feed answer packed in a struct
struct PriceFeedAnswer {
    int256 price;
    uint256 updatedAt;
    bool success;
}

/// @notice Represents an entry in the price feed map of a price oracle
/// @dev    `stalenessPeriod` is always 0 if price oracle's version is below `3_10`
struct PriceFeedMapEntry {
    address token;
    bool reserve;
    address priceFeed;
    uint32 stalenessPeriod;
}

/// @notice Represents a node in the price feed "tree"
/// @param  baseParams Base parameters
/// @param  description Price feed description
/// @param  decimals Price feed's decimals (might not be equal to 8 for lower-level)
/// @param  skipCheck Whether price feed implements its own staleness and sanity check, defaults to `false`
/// @param  updatable Whether it is an on-demand updatable (aka pull) price feed, defaults to `false`
/// @param  underlyingFeeds Array of underlying feeds, filled when `priceFeed` is nested
/// @param  underlyingStalenessPeriods Staleness periods of underlying feeds, filled when `priceFeed` is nested
/// @param  answer Price feed answer packed in a struct
struct PriceFeedTreeNode {
    BaseParams baseParams;
    string description;
    uint8 decimals;
    bool skipCheck;
    bool updatable;
    address[] underlyingFeeds;
    uint32[] underlyingStalenessPeriods;
    PriceFeedAnswer answer;
}

/// @notice Price oracle state
/// @param  baseParams Base parameters
/// @param  priceFeedMap Set of entries in the map `(token, reserve)` => `(priceFeed, stalenessPeirod)`.
///         These are all the price feeds one can actually query via the price oracle.
/// @param  priceFeedTree Set of nodes in a tree-like structure that contains detailed info of both feeds
///         from `priceFeedMap` and their underlying feeds, in case former are nested, which can help to
///         determine what underlying feeds should be updated to query the nested one.
struct PriceOracleState {
    BaseParams baseParams;
    PriceFeedMapEntry[] priceFeedMap;
    PriceFeedTreeNode[] priceFeedTree;
}
