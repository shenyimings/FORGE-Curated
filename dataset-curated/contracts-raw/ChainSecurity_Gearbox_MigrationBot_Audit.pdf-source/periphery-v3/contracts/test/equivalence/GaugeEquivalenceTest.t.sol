// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023.
pragma solidity ^0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Test} from "forge-std/Test.sol";
import {IDataCompressorV3, GaugeInfo as GaugeInfoOld} from "../interfaces/IDataCompressorV3.sol";
import {GaugeCompressor} from "../../compressors/GaugeCompressor.sol";
import {GaugeInfo} from "../../types/GaugeInfo.sol";
import {MarketFilter} from "../../types/Filters.sol";
import "forge-std/console.sol";

contract GaugeCompressorEquivalenceTest is Test {
    using Address for address;

    IDataCompressorV3 public dc3;
    GaugeCompressor public gc;

    function test_GCE_01_GaugeCompressor_equivalence() public {
        address gaugeCompressor = vm.envOr("GAUGE_COMPRESSOR", address(0));
        address dataCompressor = vm.envOr("DATA_COMPRESSOR", address(0));
        address stakerAddr = vm.envOr("STAKER_ADDRESS", address(0));

        if (
            gaugeCompressor == address(0) || dataCompressor == address(0) || !gaugeCompressor.isContract()
                || !dataCompressor.isContract()
        ) {
            console.log(
                "GaugeCompressor or DataCompressor not set, or not a contract. Skipping gauge compressor equivalence test."
            );
            return;
        }

        gc = GaugeCompressor(gaugeCompressor);
        dc3 = IDataCompressorV3(dataCompressor);

        MarketFilter memory filter =
            MarketFilter({configurators: new address[](0), pools: new address[](0), underlying: address(0)});

        GaugeInfo[] memory gauges = gc.getGauges(filter, stakerAddr);
        GaugeInfoOld[] memory gaugesOld = dc3.getGaugesV3Data(stakerAddr);

        assertEq(gauges.length, gaugesOld.length, "Gauges data length mismatch");

        for (uint256 i; i < gauges.length; i++) {
            assertEq(gauges[i].addr, gaugesOld[i].addr, "Gauge address mismatch");
            assertEq(gauges[i].pool, gaugesOld[i].pool, "Gauge pool mismatch");
            assertEq(gauges[i].symbol, gaugesOld[i].symbol, "Gauge symbol mismatch");
            assertEq(gauges[i].name, gaugesOld[i].name, "Gauge name mismatch");
            assertEq(gauges[i].underlying, gaugesOld[i].underlying, "Gauge underlying mismatch");
            assertEq(gauges[i].epochLastUpdate, gaugesOld[i].currentEpoch, "Gauge current epoch mismatch");
            assertEq(gauges[i].epochFrozen, gaugesOld[i].epochFrozen, "Gauge epoch frozen mismatch");

            assertEq(
                gauges[i].quotaParams.length, gaugesOld[i].quotaParams.length, "Gauge quota params length mismatch"
            );
            for (uint256 j; j < gauges[i].quotaParams.length; j++) {
                assertEq(
                    gauges[i].quotaParams[j].token, gaugesOld[i].quotaParams[j].token, "Gauge quota token mismatch"
                );
                assertEq(
                    gauges[i].quotaParams[j].minRate,
                    gaugesOld[i].quotaParams[j].minRate,
                    "Gauge quota min rate mismatch"
                );
                assertEq(
                    gauges[i].quotaParams[j].maxRate,
                    gaugesOld[i].quotaParams[j].maxRate,
                    "Gauge quota max rate mismatch"
                );
                assertEq(
                    gauges[i].quotaParams[j].totalVotesLpSide,
                    gaugesOld[i].quotaParams[j].totalVotesLpSide,
                    "Gauge quota total votes lp side mismatch"
                );
                assertEq(
                    gauges[i].quotaParams[j].totalVotesCaSide,
                    gaugesOld[i].quotaParams[j].totalVotesCaSide,
                    "Gauge quota total votes ca side mismatch"
                );
                assertEq(
                    gauges[i].quotaParams[j].stakerVotesLpSide,
                    gaugesOld[i].quotaParams[j].stakerVotesLpSide,
                    "Gauge quota staker votes lp side mismatch"
                );
                assertEq(
                    gauges[i].quotaParams[j].stakerVotesCaSide,
                    gaugesOld[i].quotaParams[j].stakerVotesCaSide,
                    "Gauge quota staker votes ca side mismatch"
                );
            }
        }
    }
}
