// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@morpho-blue-oracles/morpho-chainlink/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ERC4626Feed
 * @notice Chainlink price feed compatible oracle for ERC4626 vaults
 * @dev Implements AggregatorV3Interface to provide the price of a vault share
 *      in terms of the underlying asset
 */
contract ERC4626Feed is AggregatorV3Interface {
    using Math for uint256;

    /// @notice Version of the price feed implementation
    uint256 public constant version = 1;
    
    /// @notice The ERC4626 vault for which this oracle provides prices
    IERC4626 public immutable vault;
    
    /// @notice The underlying token of the vault
    IERC20Metadata public immutable token;
    
    /// @notice The number of decimals in the returned price
    uint8 public immutable decimals;
    
    /// @notice Human-readable description of the price feed (e.g., "sUSDS / USDS")
    string public description;

    /// @notice One unit of vault shares (e.g., 1e18 for 18 decimals)
    uint256 public immutable ONE_SHARE;
    
    /// @notice One unit of the underlying asset (e.g., 1e18 for 18 decimals)
    uint256 public immutable ONE_ASSET;
    
    /// @notice Scaling factor numerator used to adjust price to the desired decimals
    uint256 public immutable SCALING_NUMERATOR;
    
    /// @notice Scaling factor denominator used to adjust price to the desired decimals
    uint256 public immutable SCALING_DENOMINATOR;

    /**
     * @notice Constructs a new ERC4626Feed oracle
     * @param _vault The ERC4626 vault for which to provide a price feed
     * @param _decimals The number of decimals for the oracle output (0 to use the token's decimals)
     */
    constructor(IERC4626 _vault, uint8 _decimals) {
        vault = _vault;
        token = IERC20Metadata(_vault.asset());
        ONE_SHARE = 10 ** vault.decimals();
        ONE_ASSET = 10 ** token.decimals();
        
        // If decimals is 0, use the token's decimals
        if (_decimals == 0) {
            decimals = token.decimals();
        } else {
            decimals = _decimals;
        }
        
        // Calculate scaling factors to adjust between token decimals and oracle decimals
        uint256 token_decimals = token.decimals();
        if (decimals > token_decimals) {
            SCALING_NUMERATOR = 10 ** (decimals - token_decimals);
            SCALING_DENOMINATOR = 1;
        } else {
            SCALING_NUMERATOR = 1;
            SCALING_DENOMINATOR = 10 ** (token_decimals - decimals);
        }
        
        // Set description to "VaultSymbol / TokenSymbol" format
        description = string.concat(vault.symbol(), " / ", token.symbol());
    }

    /**
     * @notice Get the current price of one vault share in terms of the underlying asset
     * @dev Price is scaled to match the specified decimals
     * @return The current price with appropriate decimal scaling
     */
    function getPrice() public view returns (uint256) {
        uint256 price = vault.convertToAssets(ONE_SHARE);
        return SCALING_NUMERATOR.mulDiv(price, SCALING_DENOMINATOR);
    }

    /**
     * @notice Internal function to get the latest round data
     * @dev Used by both latestRoundData and getRoundData
     * @return roundId The round ID (always 1)
     * @return answer The price of one vault share in terms of the underlying asset
     * @return startedAt The timestamp when the round started (current block timestamp)
     * @return updatedAt The timestamp when the round was updated (current block timestamp)
     * @return answeredInRound The round ID in which the answer was computed (always 1)
     */
    function _latestRoundData() internal view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        uint256 price = getPrice();
        uint256 timestamp = block.timestamp;
        return (1, int256(price), timestamp, timestamp, 1);
    }

    /**
     * @notice Get the latest round data (implements AggregatorV3Interface)
     * @return roundId The round ID (always 1)
     * @return answer The price of one vault share in terms of the underlying asset
     * @return startedAt The timestamp when the round started (current block timestamp)
     * @return updatedAt The timestamp when the round was updated (current block timestamp)
     * @return answeredInRound The round ID in which the answer was computed (always 1)
     */
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return _latestRoundData();
    }

    /**
     * @notice Get data from a specific round (implements AggregatorV3Interface)
     * @dev This contract does not maintain historical data, so it always returns the latest data
     * @param _roundId The round ID (ignored)
     * @return roundId The round ID (always 1)
     * @return answer The price of one vault share in terms of the underlying asset
     * @return startedAt The timestamp when the round started (current block timestamp)
     * @return updatedAt The timestamp when the round was updated (current block timestamp)
     * @return answeredInRound The round ID in which the answer was computed (always 1)
     */
    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return _latestRoundData();
    }
}
