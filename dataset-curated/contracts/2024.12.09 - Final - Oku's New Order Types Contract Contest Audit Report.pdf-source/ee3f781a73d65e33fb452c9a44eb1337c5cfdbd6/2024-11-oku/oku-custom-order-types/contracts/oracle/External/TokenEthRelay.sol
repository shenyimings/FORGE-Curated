// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../IOracleRelay.sol";
import "../../interfaces/chainlink/IAggregator.sol";
//import "../../interfaces/openzeppelin/ERC20.sol";

///@notice Compares a token price to ETH instead of USD
///@notice Should still return the USD price in 1e8 terms
contract TokenEthRelay is IOracleRelay {
    IAggregator public immutable tokenFeed;

    address public immutable underlying;
    IOracleRelay public immutable ethOracle;

    constructor(address _underlying, IAggregator _tokenFeed, IOracleRelay _ethOracle) {
        underlying = _underlying;
        tokenFeed = _tokenFeed;
        ethOracle = _ethOracle;
    }

    function currentValue() external view override returns (uint256) {
        int256 latest = tokenFeed.latestAnswer();
        require(latest > 0, "chainlink: px < 0");

        uint256 ethPrice = ethOracle.currentValue();

        //scale
        return (uint256(latest) / ethPrice * 1e5);//3719733
    }
}
