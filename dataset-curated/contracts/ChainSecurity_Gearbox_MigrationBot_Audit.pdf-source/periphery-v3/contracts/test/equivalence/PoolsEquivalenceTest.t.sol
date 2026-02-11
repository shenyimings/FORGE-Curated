// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023.
pragma solidity ^0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Test} from "forge-std/Test.sol";
import {IDataCompressorV3, PoolData} from "../interfaces/IDataCompressorV3.sol";
import {MarketCompressor} from "../../compressors/MarketCompressor.sol";
import {MarketData} from "../../types/MarketData.sol";
import {MarketFilter} from "../../types/Filters.sol";
import "forge-std/console.sol";

contract PoolsEquivalenceTest is Test {
    using Address for address;

    IDataCompressorV3 public dc3;
    MarketCompressor public mc;

    function test_PCE_01_PoolCompressor_equivalence() public {
        address marketCompressor = vm.envOr("MARKET_COMPRESSOR", address(0));
        address dataCompressor = vm.envOr("DATA_COMPRESSOR", address(0));

        if (
            marketCompressor == address(0) || dataCompressor == address(0) || !marketCompressor.isContract()
                || !dataCompressor.isContract()
        ) {
            console.log(
                "MarketCompressor or DataCompressor not set, or not a contract. Skipping pool compressor equivalence test."
            );
            return;
        }

        mc = MarketCompressor(marketCompressor);
        dc3 = IDataCompressorV3(dataCompressor);

        MarketFilter memory filter =
            MarketFilter({configurators: new address[](0), pools: new address[](0), underlying: address(0)});

        MarketData[] memory markets = mc.getMarkets(filter);
        PoolData[] memory poolsOld = dc3.getPoolsV3List();

        assertEq(markets.length, poolsOld.length, "Pools data length mismatch");

        for (uint256 i; i < markets.length; i++) {
            assertEq(markets[i].pool.baseParams.addr, poolsOld[i].addr, "Pool address mismatch");
            assertEq(markets[i].pool.underlying, poolsOld[i].underlying, "Pool underlying mismatch");
            assertEq(markets[i].pool.symbol, poolsOld[i].symbol, "Pool symbol mismatch");
            assertEq(markets[i].pool.name, poolsOld[i].name, "Pool name mismatch");
            assertEq(
                markets[i].pool.baseInterestIndex, poolsOld[i].baseInterestIndex, "Pool baseInterestIndex mismatch"
            );
            assertEq(
                markets[i].pool.availableLiquidity, poolsOld[i].availableLiquidity, "Pool availableLiquidity mismatch"
            );
            assertEq(
                markets[i].pool.expectedLiquidity, poolsOld[i].expectedLiquidity, "Pool expectedLiquidity mismatch"
            );
            assertEq(markets[i].pool.totalBorrowed, poolsOld[i].totalBorrowed, "Pool totalBorrowed mismatch");
            assertEq(markets[i].pool.totalDebtLimit, poolsOld[i].totalDebtLimit, "Pool totalDebtLimit mismatch");
            assertEq(markets[i].pool.totalSupply, poolsOld[i].totalSupply, "Pool totalSupply mismatch");
            assertEq(markets[i].pool.supplyRate, poolsOld[i].supplyRate, "Pool supplyRate mismatch");
            assertEq(markets[i].pool.baseInterestRate, poolsOld[i].baseInterestRate, "Pool baseInterestRate mismatch");
            assertEq(markets[i].pool.dieselRate, poolsOld[i].dieselRate_RAY, "Pool dieselRate mismatch");
            assertEq(markets[i].pool.withdrawFee, poolsOld[i].withdrawFee, "Pool withdrawFee mismatch");
            assertEq(
                markets[i].pool.baseInterestIndexLU,
                poolsOld[i].baseInterestIndexLU,
                "Pool baseInterestIndexLU mismatch"
            );
            assertEq(markets[i].pool.isPaused, poolsOld[i].isPaused, "Pool isPaused mismatch");

            assertEq(markets[i].pool.quotaKeeper, poolsOld[i].poolQuotaKeeper, "Pool quota keeper address mismatch");
            assertEq(
                markets[i].pool.interestRateModel,
                poolsOld[i].lirm.interestRateModel,
                "Interest rate model address mismatch"
            );

            if (poolsOld[i].lirm.interestRateModel != address(0)) {
                assertEq(
                    markets[i].interestRateModel.baseParams.version,
                    poolsOld[i].lirm.version,
                    "Interest rate model version mismatch"
                );
            }

            assertEq(
                markets[i].pool.creditManagerDebtParams.length,
                poolsOld[i].creditManagerDebtParams.length,
                "Credit manager debt params length mismatch"
            );

            for (uint256 j; j < markets[i].pool.creditManagerDebtParams.length; j++) {
                assertEq(
                    markets[i].pool.creditManagerDebtParams[j].creditManager,
                    poolsOld[i].creditManagerDebtParams[j].creditManager,
                    "Credit manager address mismatch"
                );
                assertEq(
                    markets[i].pool.creditManagerDebtParams[j].borrowed,
                    poolsOld[i].creditManagerDebtParams[j].borrowed,
                    "Credit manager borrowed mismatch"
                );
                assertEq(
                    markets[i].pool.creditManagerDebtParams[j].limit,
                    poolsOld[i].creditManagerDebtParams[j].limit,
                    "Credit manager limit mismatch"
                );
                assertEq(
                    markets[i].pool.creditManagerDebtParams[j].available,
                    poolsOld[i].creditManagerDebtParams[j].availableToBorrow,
                    "Credit manager available mismatch"
                );
            }

            assertEq(
                markets[i].quotaKeeper.quotas.length, poolsOld[i].quotas.length, "Pool quota params length mismatch"
            );

            for (uint256 j; j < markets[i].quotaKeeper.quotas.length; j++) {
                assertEq(markets[i].quotaKeeper.quotas[j].token, poolsOld[i].quotas[j].token, "Quota token mismatch");
                assertEq(markets[i].quotaKeeper.quotas[j].rate, poolsOld[i].quotas[j].rate, "Quota rate mismatch");
                assertEq(
                    markets[i].quotaKeeper.quotas[j].quotaIncreaseFee,
                    poolsOld[i].quotas[j].quotaIncreaseFee,
                    "Quota increase fee mismatch"
                );
                assertEq(
                    markets[i].quotaKeeper.quotas[j].totalQuoted,
                    poolsOld[i].quotas[j].totalQuoted,
                    "Quota total quoted mismatch"
                );
                assertEq(markets[i].quotaKeeper.quotas[j].limit, poolsOld[i].quotas[j].limit, "Quota limit mismatch");
                assertEq(
                    markets[i].quotaKeeper.quotas[j].isActive, poolsOld[i].quotas[j].isActive, "Quota isActive mismatch"
                );
            }
        }
    }
}
