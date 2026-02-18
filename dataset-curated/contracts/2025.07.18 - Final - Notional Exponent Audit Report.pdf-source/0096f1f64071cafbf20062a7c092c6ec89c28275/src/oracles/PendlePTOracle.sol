// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.8.29;

import {IPMarket, IPOracle, PENDLE_ORACLE} from "../interfaces/IPendle.sol";
import {AggregatorV2V3Interface} from "../interfaces/AggregatorV2V3Interface.sol";
import {AbstractCustomOracle} from "./AbstractCustomOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TypeConvert} from "../utils/TypeConvert.sol";

contract PendlePTOracle is AbstractCustomOracle {
    using TypeConvert for uint256;

    address public immutable pendleMarket;
    uint32 public immutable twapDuration;
    bool public immutable useSyOracleRate;

    AggregatorV2V3Interface public immutable baseToUSDOracle;
    int256 public immutable baseToUSDDecimals;
    int256 public immutable ptDecimals;
    bool public immutable invertBase;

    constructor (
        address pendleMarket_,
        AggregatorV2V3Interface baseToUSDOracle_,
        bool invertBase_,
        bool useSyOracleRate_,
        uint32 twapDuration_,
        string memory description_,
        address sequencerUptimeOracle_
    ) AbstractCustomOracle(
        description_,
        sequencerUptimeOracle_
    ) {
        pendleMarket = pendleMarket_;
        twapDuration = twapDuration_;
        useSyOracleRate = useSyOracleRate_;

        baseToUSDOracle = baseToUSDOracle_;
        invertBase = invertBase_;

        uint8 _baseDecimals = baseToUSDOracle_.decimals();
        (/* */, address pt, /* */) = IPMarket(pendleMarket_).readTokens();
        uint8 _ptDecimals = ERC20(pt).decimals();

        require(_baseDecimals <= 18);
        require(_ptDecimals <= 18);

        baseToUSDDecimals = int256(10**_baseDecimals);
        ptDecimals = int256(10**_ptDecimals);

        (
            bool increaseCardinalityRequired,
            /* */,
            bool oldestObservationSatisfied
        ) = PENDLE_ORACLE.getOracleState(pendleMarket, twapDuration);
        // If this fails then we need to increase the cardinality in the Pendle system
        require(!increaseCardinalityRequired && oldestObservationSatisfied, "Oracle Init");
    }

    /// @dev ptRate is always returned in 1e18 decimals
    function _getPTRate() internal view returns (int256) {
        uint256 ptRate = useSyOracleRate ?
            PENDLE_ORACLE.getPtToSyRate(pendleMarket, twapDuration) :
            PENDLE_ORACLE.getPtToAssetRate(pendleMarket, twapDuration);
        return ptRate.toInt();
    }

    function _calculateBaseToQuote() internal view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        int256 baseToUSD;
        (
            roundId,
            baseToUSD,
            startedAt,
            updatedAt,
            answeredInRound
        ) = baseToUSDOracle.latestRoundData();
        require(baseToUSD > 0, "Chainlink Rate Error");
        // Overflow and div by zero not possible
        if (invertBase) baseToUSD = (baseToUSDDecimals * baseToUSDDecimals) / baseToUSD;

        int256 ptRate = _getPTRate();
        answer = (ptRate * baseToUSD) / baseToUSDDecimals;
    }
}