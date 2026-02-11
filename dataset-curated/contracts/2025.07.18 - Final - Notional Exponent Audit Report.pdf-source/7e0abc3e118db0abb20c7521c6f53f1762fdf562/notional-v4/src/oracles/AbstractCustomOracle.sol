// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.8.29;

import {AggregatorV2V3Interface} from "../interfaces/AggregatorV2V3Interface.sol";

/// @notice Defines a custom oracle that implements the AggregatorV2V3Interface. Used to
/// get the price of more exotic assets like LP tokens, PT tokens, etc. Returns the price
/// in USD terms. Used inside the TradingModule to calculate the price of arbitrary token
/// pairs.
abstract contract AbstractCustomOracle is AggregatorV2V3Interface {

    uint256 public override constant version = 1;
    string public override description;

    uint8 public override constant decimals = 18;

    AggregatorV2V3Interface public immutable sequencerUptimeOracle;
    uint256 public constant SEQUENCER_UPTIME_GRACE_PERIOD = 1 hours;

    constructor(
        string memory description_,
        address sequencerUptimeOracle_
    ) {
        description = description_;
        sequencerUptimeOracle = AggregatorV2V3Interface(sequencerUptimeOracle_);
    }

    function _calculateBaseToQuote() internal view virtual returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    function _checkSequencer() private view {
        // See: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
        if (address(sequencerUptimeOracle) != address(0)) {
            (
                /*uint80 roundID*/,
                int256 answer,
                uint256 startedAt,
                /*uint256 updatedAt*/,
                /*uint80 answeredInRound*/
            ) = sequencerUptimeOracle.latestRoundData();
            require(answer == 0, "Sequencer Down");
            require(SEQUENCER_UPTIME_GRACE_PERIOD < block.timestamp - startedAt, "Sequencer Grace Period");
        }
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        _checkSequencer();
        return _calculateBaseToQuote();
    }

    function latestAnswer() external view override returns (int256 answer) {
        (/* */, answer, /* */, /* */, /* */) = _calculateBaseToQuote();
    }

    function latestTimestamp() external view override returns (uint256 updatedAt) {
        (/* */, /* */, /* */, updatedAt, /* */) = _calculateBaseToQuote();
    }

    function latestRound() external view override returns (uint256 roundId) {
        (roundId, /* */, /* */, /* */, /* */) = _calculateBaseToQuote();
    }

    /// @dev Unused in the trading module
    function getRoundData(uint80 /* _roundId */) external pure override returns (
        uint80 /* roundId */,
        int256 /* answer */,
        uint256 /* startedAt */,
        uint256 /* updatedAt */,
        uint80 /* answeredInRound */
    ) {
        revert();
    }

    /// @dev Unused in the trading module
    function getAnswer(uint256 /* roundId */) external pure override returns (int256) { revert(); }

    /// @dev Unused in the trading module
    function getTimestamp(uint256 /* roundId */) external pure override returns (uint256) { revert(); }
}