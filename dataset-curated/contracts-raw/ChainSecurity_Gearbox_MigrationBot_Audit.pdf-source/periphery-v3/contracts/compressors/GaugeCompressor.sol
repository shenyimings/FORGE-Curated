// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IGaugeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IGaugeV3.sol";
import {IGearStakingV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IGearStakingV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";

import {IGaugeCompressor} from "../interfaces/IGaugeCompressor.sol";

import {AP_GAUGE_COMPRESSOR} from "../libraries/Literals.sol";

import {MarketFilter} from "../types/Filters.sol";
import {GaugeInfo, GaugeQuotaParams} from "../types/GaugeInfo.sol";

import {BaseCompressor} from "./BaseCompressor.sol";

/// @title Gauge Compressor
/// @notice Collects data from gauges for use in the dApp
contract GaugeCompressor is BaseCompressor, IGaugeCompressor {
    uint256 public constant version = 3_10;
    bytes32 public constant contractType = AP_GAUGE_COMPRESSOR;

    constructor(address addressProvider_) BaseCompressor(addressProvider_) {}

    /// @dev Returns gauge info for all gauges matching the filter
    /// @param filter Filter parameters for pools
    /// @param staker Address of the staker to get votes for (can be address(0) if not needed)
    function getGauges(MarketFilter memory filter, address staker)
        external
        view
        override
        returns (GaugeInfo[] memory result)
    {
        Pool[] memory pools = _getPools(filter);
        uint256 len = pools.length;
        result = new GaugeInfo[](len);
        uint256 validGauges;

        for (uint256 i; i < len; ++i) {
            address pool = pools[i].addr;
            IPoolQuotaKeeperV3 pqk = _getPoolQuotaKeeper(pool);
            address gauge = pqk.gauge();

            if (gauge == address(0)) continue;

            try this.getGaugeInfo(gauge, staker) returns (GaugeInfo memory gaugeInfo) {
                result[validGauges++] = gaugeInfo;
            } catch {
                continue;
            }
        }
        assembly {
            mstore(result, validGauges)
        }
    }

    /// @dev Returns gauge info for a specific gauge
    /// @param gauge Gauge address
    /// @param staker Address of the staker to get votes for (can be address(0) if not needed)
    function getGaugeInfo(address gauge, address staker) public view override returns (GaugeInfo memory result) {
        if (!_isValidGauge(gauge)) revert("INVALID_GAUGE_TYPE");

        address pool = IGaugeV3(gauge).pool();
        IPoolQuotaKeeperV3 pqk = _getPoolQuotaKeeper(pool);
        return _getGaugeInfo(gauge, pool, pqk, staker);
    }

    /// @dev Internal function to check if an address is a valid gauge
    /// @param gauge Address to check
    /// @return True if the address is a valid gauge (either old or new version)
    function _isValidGauge(address gauge) internal view returns (bool) {
        try IGaugeV3(gauge).contractType() returns (bytes32 cType) {
            return cType == "RATE_KEEPER::GAUGE";
        } catch {
            return true;
        }
    }

    /// @dev Internal function to get gauge info
    function _getGaugeInfo(address gauge, address pool, IPoolQuotaKeeperV3 pqk, address staker)
        internal
        view
        returns (GaugeInfo memory gaugeInfo)
    {
        gaugeInfo.addr = gauge;
        gaugeInfo.pool = pool;
        gaugeInfo.symbol = IPoolV3(pool).symbol();
        gaugeInfo.name = IPoolV3(pool).name();
        gaugeInfo.underlying = IPoolV3(pool).asset();
        gaugeInfo.voter = IGaugeV3(gauge).voter();

        gaugeInfo.currentEpoch = IGearStakingV3(gaugeInfo.voter).getCurrentEpoch();
        gaugeInfo.epochLastUpdate = IGaugeV3(gauge).epochLastUpdate();
        gaugeInfo.epochFrozen = IGaugeV3(gauge).epochFrozen();

        address[] memory quotaTokens = pqk.quotedTokens();
        uint256 quotaTokensLen = quotaTokens.length;
        gaugeInfo.quotaParams = new GaugeQuotaParams[](quotaTokensLen);

        for (uint256 j; j < quotaTokensLen; ++j) {
            GaugeQuotaParams memory quotaParams = gaugeInfo.quotaParams[j];
            address token = quotaTokens[j];
            quotaParams.token = token;

            (quotaParams.minRate, quotaParams.maxRate, quotaParams.totalVotesLpSide, quotaParams.totalVotesCaSide) =
                IGaugeV3(gauge).quotaRateParams(token);

            // Get staker votes if staker address is provided
            if (staker != address(0)) {
                (quotaParams.stakerVotesLpSide, quotaParams.stakerVotesCaSide) =
                    IGaugeV3(gauge).userTokenVotes(staker, token);
            }
        }
    }

    /// @dev Internal function to get pool quota keeper
    function _getPoolQuotaKeeper(address pool) internal view returns (IPoolQuotaKeeperV3) {
        return IPoolQuotaKeeperV3(IPoolV3(pool).poolQuotaKeeper());
    }
}
