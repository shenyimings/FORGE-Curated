// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseChainlinkOracle} from "./BaseChainlinkOracle.sol";
import {AggregatorV3Interface} from "../../external/AggregatorV3Interface.sol";
import {Common} from "../../libraries/Common.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";

/// @title ChainlinkOracle
/// @notice PriceOracle adapter for Chainlink push-based price feeds.
contract ChainlinkOracle is BaseChainlinkOracle {
    /// @notice The max staleness mapped to feed address.
    mapping(address => uint256) public feedToMaxStaleness;
    /// @dev Used for correcting for the decimals of base and quote.
    uint8 public constant QUOTE_DECIMALS = 18;
    /// @notice Name of the oracle.
    string public constant name = "Chainlink sBold V1";
    /// @notice The address of the token to USD.
    Feed public feed;

    /// @notice Deploys a Chainlink price oracle.
    /// @param _base The address of the base asset.
    /// @param _feed The structure for the ETH to USD feed.
    constructor(address _base, Feed memory _feed) {
        Common.revertZeroAddress(_base);
        Common.revertZeroAddress(_feed.addr);

        if (_feed.maxStaleness < MAX_STALENESS_LOWER_BOUND || _feed.maxStaleness > MAX_STALENESS_UPPER_BOUND) {
            revert InvalidMaxStaleness();
        }

        base = _base;
        feed = _feed;
    }

    /// @inheritdoc BaseChainlinkOracle
    function getQuote(uint256 inAmount, address _base) external view override returns (uint256) {
        if (!isBaseSupported(_base)) revert InvalidFeed();

        uint256 baseToUsdPrice = _getLatestAnswer(feed);

        return (inAmount * baseToUsdPrice) / 10 ** Constants.ORACLE_PRICE_PRECISION;
    }

    /// @inheritdoc BaseChainlinkOracle
    function isBaseSupported(address _base) public view override returns (bool) {
        return base == _base;
    }
}
