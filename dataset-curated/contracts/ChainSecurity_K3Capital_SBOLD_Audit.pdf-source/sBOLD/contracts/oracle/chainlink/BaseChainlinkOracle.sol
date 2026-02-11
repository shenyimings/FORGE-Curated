// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {AggregatorV3Interface} from "../../external/AggregatorV3Interface.sol";
import {Common} from "../../libraries/Common.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";

/// @title BaseChainlinkOracle
/// @notice Base adaptation for Chainlink price oracle.
contract BaseChainlinkOracle is IPriceOracle {
    /// @notice The feed structure for price oracle adapters.
    struct Feed {
        address addr;
        uint96 maxStaleness;
    }

    /// @notice The minimum permitted value for `maxStaleness`.
    uint256 internal constant MAX_STALENESS_LOWER_BOUND = 1 minutes;
    /// @notice The maximum permitted value for `maxStaleness`.
    uint256 internal constant MAX_STALENESS_UPPER_BOUND = 72 hours;
    /// @notice The address of the asset.
    address public immutable base;

    /// @inheritdoc IPriceOracle
    function getQuote(uint256 inAmount, address _base) external view virtual returns (uint256) {}

    /// @inheritdoc IPriceOracle
    function isBaseSupported(address _base) external view virtual returns (bool) {}

    /// @notice Returns scaled aggregator price for feed.
    function _getLatestAnswer(Feed memory _feed) internal view returns (uint256) {
        AggregatorV3Interface feedInstance = AggregatorV3Interface(_feed.addr);

        // Price validity check
        (, int256 answer, , uint256 updatedAt, ) = feedInstance.latestRoundData();
        if (answer <= 0) revert InvalidPrice();

        // Staleness check
        uint256 staleness = block.timestamp - updatedAt;
        if (staleness > _feed.maxStaleness) revert TooStalePrice();

        // Return scaled price
        return _scale(answer, feedInstance.decimals());
    }

    /// @notice Returns scaled price with precision of 18.
    function _scale(int256 _price, uint256 _decimals) private pure returns (uint256) {
        return uint256(_price) * 10 ** (Constants.ORACLE_PRICE_PRECISION - _decimals);
    }
}
