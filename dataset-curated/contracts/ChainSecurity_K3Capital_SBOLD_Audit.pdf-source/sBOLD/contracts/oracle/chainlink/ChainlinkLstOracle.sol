// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "../../external/AggregatorV3Interface.sol";
import {BaseChainlinkOracle} from "./BaseChainlinkOracle.sol";
import {Decimals} from "../../libraries/helpers/Decimals.sol";
import {Common} from "../../libraries/Common.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";

/// @title ChainlinkLstOracle
/// @notice PriceOracle adapter for Chainlink push-based price feeds, specific for liquid-staking tokens.
contract ChainlinkLstOracle is BaseChainlinkOracle {
    /// @notice The max staleness mapped to feed address.
    mapping(address => uint256) public feedToMaxStaleness;
    /// @notice Name of the oracle.
    string public constant name = "Chainlink LST sBold V1";
    /// @notice The address of the ETH to USD.
    Feed public ethUsdFeed;
    /// @notice The address of the LST to ETH feed.
    Feed public lstEthFeed;

    /// @notice Deploys a Chainlink price oracle for liquid-staking tokens.
    /// @param _base The address of the base asset.
    /// @param _ethUsdFeed The structure for the ETH to USD feed.
    /// @param _lstEthFeed The structure for the LST to ETH feed.
    constructor(address _base, Feed memory _ethUsdFeed, Feed memory _lstEthFeed) {
        Common.revertZeroAddress(_base);
        Common.revertZeroAddress(_ethUsdFeed.addr);
        Common.revertZeroAddress(_lstEthFeed.addr);

        if (
            _ethUsdFeed.maxStaleness < MAX_STALENESS_LOWER_BOUND || _ethUsdFeed.maxStaleness > MAX_STALENESS_UPPER_BOUND
        ) {
            revert InvalidMaxStaleness();
        }

        if (
            _lstEthFeed.maxStaleness < MAX_STALENESS_LOWER_BOUND || _lstEthFeed.maxStaleness > MAX_STALENESS_UPPER_BOUND
        ) {
            revert InvalidMaxStaleness();
        }

        base = _base;
        ethUsdFeed = _ethUsdFeed;
        lstEthFeed = _lstEthFeed;
    }

    /// @inheritdoc BaseChainlinkOracle
    function getQuote(uint256 inAmount, address) external view override returns (uint256) {
        uint256 lstUsdPrice = _fetchPrice();

        return (inAmount * lstUsdPrice) / 10 ** Decimals.getDecimals(base);
    }

    /// @inheritdoc BaseChainlinkOracle
    function isBaseSupported(address _base) external view override returns (bool) {
        return base == _base;
    }

    /// @notice Extracts price for ETH to USD and LST to ETH feeds.
    /// @dev The returned price is the denomination of the LST to USD.
    function _fetchPrice() internal view returns (uint256) {
        uint256 ethInUsd = _getLatestAnswer(ethUsdFeed);
        uint256 lstInEth = _getLatestAnswer(lstEthFeed);

        // Calculate the price for LST to USD
        return (ethInUsd * lstInEth) / 10 ** Constants.ORACLE_PRICE_PRECISION;
    }
}
