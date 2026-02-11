// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {Decimals} from "../../libraries/helpers/Decimals.sol";
import {Common} from "../../libraries/Common.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";

/// @title PythOracle
/// @notice PriceOracle adapter for Pyth pull-based price feeds.
contract PythOracle is IPriceOracle, Ownable {
    /// @notice The maximum length of time that a price can be in the future.
    uint256 internal constant MAX_AHEADNESS = 1 minutes;
    /// @notice The maximum permitted value for `maxStaleness`.
    uint256 internal constant MAX_STALENESS_UPPER_BOUND = 15 minutes;
    /// @notice The minimum permitted value for `maxConfWidth`.
    /// @dev Equal to 0.1%.
    uint256 internal constant MAX_CONF_WIDTH_LOWER_BOUND = 10;
    /// @notice The maximum permitted value for `maxConfWidth`.
    /// @dev Equal to 5%.
    uint256 internal constant MAX_CONF_WIDTH_UPPER_BOUND = 500;
    /// @dev The smallest PythStruct exponent that the oracle can handle.
    int256 internal constant MIN_EXPONENT = -20;
    /// @dev The largest PythStruct exponent that the oracle can handle.
    int256 internal constant MAX_EXPONENT = 12;
    /// @notice Name of the oracle.
    string public constant name = "Pyth sBold V1";
    /// @notice The address of the Pyth oracle proxy.
    address public immutable pyth;
    /// @notice The address of the asset to convert from.
    address public immutable base;
    /// @notice The feedId of the base asset. The id of the feed in the Pyth network for the base asset address.
    /// @dev See https://pyth.network/developers/price-feed-ids.
    bytes32 public immutable feedId;
    /// @notice The decimals of the base asset.
    uint8 public immutable baseDecimals;
    /// @notice The max staleness of the feed id.
    uint256 public immutable maxStaleness;
    /// @notice The maximum allowed width of the confidence interval.
    uint256 public immutable maxConfWidth;

    /// @notice Deploys a PythOracle.
    /// @param _pyth The address of the Pyth oracle proxy.
    /// @param _base The base asset address.
    /// @param _feedId The id of the feed.
    /// @param _maxStaleness The maximum price staleness.
    /// @param _maxConfWidth The maximum width of the confidence interval in basis points.
    constructor(
        address _pyth,
        address _base,
        bytes32 _feedId,
        uint256 _maxStaleness,
        uint256 _maxConfWidth
    ) Ownable(_msgSender()) {
        Common.revertZeroAddress(_pyth);
        Common.revertZeroAddress(_base);

        if (_maxStaleness > MAX_STALENESS_UPPER_BOUND) {
            revert InvalidMaxStalenessUpperBound();
        }

        if (_maxConfWidth < MAX_CONF_WIDTH_LOWER_BOUND || _maxConfWidth > MAX_CONF_WIDTH_UPPER_BOUND) {
            revert InvalidMaxConfWidthLowerBound();
        }

        if (_feedId == bytes32(0)) {
            revert InvalidFeed();
        }

        pyth = _pyth;
        base = _base;
        maxConfWidth = _maxConfWidth;
        baseDecimals = Decimals.getDecimals(_base);
        feedId = _feedId;
        maxStaleness = _maxStaleness;
    }

    /// @inheritdoc IPriceOracle
    function getQuote(uint256 inAmount, address) external view override returns (uint256) {
        // Check if asset is configured
        if (baseDecimals == 0) revert InvalidBaseDecimals();
        // Fetch Pyth price struct and validated output
        PythStructs.Price memory priceStruct = _fetchPriceStruct(feedId);

        uint256 price = uint256(uint64(priceStruct.price));

        uint256 scale;
        if (priceStruct.expo < 0) {
            // scale down if exponent < 0
            scale = (price * 10 ** Constants.ORACLE_PRICE_PRECISION) / (10 ** uint8(int8(-priceStruct.expo)));
        } else {
            // scale up if exponent >= 0
            scale = (price * 10 ** Constants.ORACLE_PRICE_PRECISION) * (10 ** uint8(int8(priceStruct.expo)));
        }
        // Calculate amount out scaled to `ORACLE_PRICE_PRECISION`
        return (scale * inAmount) / 10 ** baseDecimals;
    }

    /// @inheritdoc IPriceOracle
    function isBaseSupported(address _base) external view returns (bool) {
        return base == _base;
    }

    /// @notice Get the latest Pyth price and perform sanity checks.
    /// @dev Revert conditions: update timestamp is too stale or too ahead, price is negative or zero,
    /// confidence interval is too wide, exponent is too large or too small.
    /// @return The Pyth price struct without modification.
    function _fetchPriceStruct(bytes32 _feedId) internal view returns (PythStructs.Price memory) {
        PythStructs.Price memory p = IPyth(pyth).getPriceUnsafe(_feedId);

        if (p.publishTime < block.timestamp) {
            // Verify that the price is not too stale
            uint256 staleness = block.timestamp - p.publishTime;
            if (staleness > maxStaleness) revert TooStalePrice();
        } else {
            // Verify that the price is not too ahead
            uint256 aheadness = p.publishTime - block.timestamp;
            if (aheadness > MAX_AHEADNESS) revert TooAheadPrice();
        }

        // Verify that the price is positive and within the confidence width.
        if (p.price <= 0 || p.conf > (uint64(p.price) * maxConfWidth) / Constants.BPS_DENOMINATOR) {
            revert InvalidPrice();
        }

        // Verify that the price exponent is within bounds.
        if (p.expo < MIN_EXPONENT || p.expo > MAX_EXPONENT) {
            revert InvalidPriceExponent();
        }

        return p;
    }
}
