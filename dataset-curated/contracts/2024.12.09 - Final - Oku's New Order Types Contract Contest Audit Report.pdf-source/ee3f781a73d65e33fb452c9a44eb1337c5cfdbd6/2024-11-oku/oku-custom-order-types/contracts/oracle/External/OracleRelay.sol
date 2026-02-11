// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../IOracleRelay.sol";
import "../../interfaces/chainlink/IAggregator.sol";

contract OracleRelay is IOracleRelay {
    IAggregator public immutable aggregator;

    address public immutable underlying;

    constructor(address _underlying, IAggregator _aggregator) {
        underlying = _underlying;
        aggregator = _aggregator;

    }

    function currentValue() external view override returns (uint256) {
        int256 latest = aggregator.latestAnswer();
        require(latest > 0, "chainlink: px < 0");
        return uint256(latest);
    }
}
