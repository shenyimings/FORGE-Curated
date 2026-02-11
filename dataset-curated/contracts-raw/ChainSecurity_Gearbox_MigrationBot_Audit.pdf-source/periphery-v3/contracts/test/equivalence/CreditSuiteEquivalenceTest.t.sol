// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023.
pragma solidity ^0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Test} from "forge-std/Test.sol";
import {IDataCompressorV3, CreditManagerData} from "../interfaces/IDataCompressorV3.sol";
import {MarketCompressor} from "../../compressors/MarketCompressor.sol";
import {MarketData} from "../../types/MarketData.sol";
import {MarketFilter} from "../../types/Filters.sol";
import "forge-std/console.sol";

contract CreditSuiteEquivalenceTest is Test {
    using Address for address;

    IDataCompressorV3 public dc3;
    MarketCompressor public mc;

    function _findCreditManager(address cmAddr, CreditManagerData[] memory creditManagersOld)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i; i < creditManagersOld.length; i++) {
            if (creditManagersOld[i].addr == cmAddr) {
                return i;
            }
        }
        revert(string.concat("No matching credit manager found for address: ", vm.toString(cmAddr)));
    }

    function test_CSE_01_CreditSuite_equivalence() public {
        address marketCompressor = vm.envOr("MARKET_COMPRESSOR", address(0));
        address dataCompressor = vm.envOr("DATA_COMPRESSOR", address(0));

        if (
            marketCompressor == address(0) || dataCompressor == address(0) || !marketCompressor.isContract()
                || !dataCompressor.isContract()
        ) {
            console.log(
                "MarketCompressor or DataCompressor not set, or not a contract. Skipping credit suite equivalence test."
            );
            return;
        }

        mc = MarketCompressor(marketCompressor);
        dc3 = IDataCompressorV3(dataCompressor);

        MarketFilter memory filter =
            MarketFilter({configurators: new address[](0), pools: new address[](0), underlying: address(0)});

        MarketData[] memory markets = mc.getMarkets(filter);
        CreditManagerData[] memory creditManagersOld = dc3.getCreditManagersV3List();

        uint256 totalCreditManagers;
        for (uint256 i; i < markets.length; i++) {
            totalCreditManagers += markets[i].creditManagers.length;
        }

        assertEq(totalCreditManagers, creditManagersOld.length, "Credit managers total count mismatch");

        // For each credit manager in markets, find its match in creditManagersOld
        for (uint256 i; i < markets.length; i++) {
            for (uint256 j; j < markets[i].creditManagers.length; j++) {
                address cmAddr = markets[i].creditManagers[j].creditManager.baseParams.addr;
                uint256 cmIndex = _findCreditManager(cmAddr, creditManagersOld);

                // Compare credit manager data
                assertEq(
                    markets[i].creditManagers[j].creditManager.name,
                    creditManagersOld[cmIndex].name,
                    "Credit manager name mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.underlying,
                    creditManagersOld[cmIndex].underlying,
                    "Credit manager underlying mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.pool,
                    creditManagersOld[cmIndex].pool,
                    "Credit manager pool mismatch"
                );

                // Compare credit facade data
                assertEq(
                    markets[i].creditManagers[j].creditFacade.baseParams.addr,
                    creditManagersOld[cmIndex].creditFacade,
                    "Credit facade address mismatch"
                );
                // assertEq(
                //     markets[i].creditManagers[j].creditFacade.baseParams.version,
                //     creditManagersOld[cmIndex].creditFacadeVersion,
                //     "Credit facade version mismatch"
                // );
                assertEq(
                    markets[i].creditManagers[j].creditFacade.degenNFT,
                    creditManagersOld[cmIndex].degenNFT,
                    "Credit facade degenNFT mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditFacade.forbiddenTokensMask,
                    creditManagersOld[cmIndex].forbiddenTokenMask,
                    "Credit facade forbidden token mask mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditFacade.isPaused,
                    creditManagersOld[cmIndex].isPaused,
                    "Credit facade isPaused mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditFacade.minDebt,
                    creditManagersOld[cmIndex].minDebt,
                    "Credit facade minDebt mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditFacade.maxDebt,
                    creditManagersOld[cmIndex].maxDebt,
                    "Credit facade maxDebt mismatch"
                );

                // Compare credit manager configuration
                assertEq(
                    markets[i].creditManagers[j].creditManager.maxEnabledTokens,
                    creditManagersOld[cmIndex].maxEnabledTokensLength,
                    "Credit manager max enabled tokens mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.feeInterest,
                    creditManagersOld[cmIndex].feeInterest,
                    "Credit manager fee interest mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.feeLiquidation,
                    creditManagersOld[cmIndex].feeLiquidation,
                    "Credit manager fee liquidation mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.liquidationDiscount,
                    creditManagersOld[cmIndex].liquidationDiscount,
                    "Credit manager liquidation discount mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.feeLiquidationExpired,
                    creditManagersOld[cmIndex].feeLiquidationExpired,
                    "Credit manager fee liquidation expired mismatch"
                );
                assertEq(
                    markets[i].creditManagers[j].creditManager.liquidationDiscountExpired,
                    creditManagersOld[cmIndex].liquidationDiscountExpired,
                    "Credit manager liquidation discount expired mismatch"
                );

                // Compare collateral tokens
                assertEq(
                    markets[i].creditManagers[j].creditManager.collateralTokens.length,
                    creditManagersOld[cmIndex].collateralTokens.length,
                    "Credit manager collateral tokens length mismatch"
                );

                for (uint256 k; k < markets[i].creditManagers[j].creditManager.collateralTokens.length; k++) {
                    assertEq(
                        markets[i].creditManagers[j].creditManager.collateralTokens[k].token,
                        creditManagersOld[cmIndex].collateralTokens[k],
                        "Credit manager collateral token address mismatch"
                    );
                    assertEq(
                        markets[i].creditManagers[j].creditManager.collateralTokens[k].liquidationThreshold,
                        creditManagersOld[cmIndex].liquidationThresholds[k],
                        "Credit manager collateral token liquidation threshold mismatch"
                    );
                }

                // Compare adapters
                assertEq(
                    markets[i].creditManagers[j].adapters.length,
                    creditManagersOld[cmIndex].adapters.length,
                    "Credit manager adapters length mismatch"
                );

                for (uint256 k; k < markets[i].creditManagers[j].adapters.length; k++) {
                    assertEq(
                        markets[i].creditManagers[j].adapters[k].baseParams.addr,
                        creditManagersOld[cmIndex].adapters[k].adapter,
                        "Credit manager adapter address mismatch"
                    );
                    assertEq(
                        markets[i].creditManagers[j].adapters[k].targetContract,
                        creditManagersOld[cmIndex].adapters[k].targetContract,
                        "Credit manager adapter target contract mismatch"
                    );
                }
            }
        }
    }
}
