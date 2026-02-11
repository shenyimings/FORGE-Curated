// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023.
pragma solidity ^0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Test} from "forge-std/Test.sol";
import {
    IDataCompressorV3,
    CreditAccountData as CreditAccountDataOld,
    TokenBalance
} from "../interfaces/IDataCompressorV3.sol";
import {MarketCompressor} from "../../compressors/MarketCompressor.sol";
import {CreditAccountCompressor} from "../../compressors/CreditAccountCompressor.sol";
import {PriceFeedCompressor} from "../../compressors/PriceFeedCompressor.sol";
import {MarketData} from "../../types/MarketData.sol";
import {CreditAccountData, TokenInfo} from "../../types/CreditAccountState.sol";
import {MarketFilter, CreditAccountFilter} from "../../types/Filters.sol";
import {PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {RedstonePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/RedstonePriceFeed.sol";
import {BaseParams} from "../../types/BaseState.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

contract CreditAccountsEquivalenceTest is Test {
    using Address for address;

    IDataCompressorV3 public dc3;
    MarketCompressor public mc;
    CreditAccountCompressor public cac;
    PriceFeedCompressor public pfc;

    function _updateAllPriceFeeds() internal {
        MarketFilter memory filter =
            MarketFilter({configurators: new address[](0), pools: new address[](0), underlying: address(0)});

        BaseParams[] memory updatablePriceFeeds = pfc.getUpdatablePriceFeeds(filter);
        for (uint256 i = 0; i < updatablePriceFeeds.length; i++) {
            _refreshUpdatablePriceFeed(updatablePriceFeeds[i].addr, updatablePriceFeeds[i].contractType);
        }
    }

    function test_CAE_01_CreditAccounts_equivalence() public {
        address marketCompressor = vm.envOr("MARKET_COMPRESSOR", address(0));
        address dataCompressor = vm.envOr("DATA_COMPRESSOR", address(0));
        address creditAccountCompressor = vm.envOr("CREDIT_ACCOUNT_COMPRESSOR", address(0));
        address priceFeedCompressor = vm.envOr("PRICE_FEED_COMPRESSOR", address(0));
        address creditManager = vm.envOr("CREDIT_MANAGER", address(0));

        if (
            marketCompressor == address(0) || dataCompressor == address(0) || creditAccountCompressor == address(0)
                || priceFeedCompressor == address(0) || creditManager == address(0) || !marketCompressor.isContract()
                || !dataCompressor.isContract() || !creditAccountCompressor.isContract()
                || !priceFeedCompressor.isContract() || !creditManager.isContract()
        ) {
            console.log(
                "MarketCompressor, DataCompressor, CreditAccountCompressor, PriceFeedCompressor or CreditManager not set, or not a contract. Skipping credit accounts equivalence test."
            );
            return;
        }

        mc = MarketCompressor(marketCompressor);
        dc3 = IDataCompressorV3(dataCompressor);
        cac = CreditAccountCompressor(creditAccountCompressor);
        pfc = PriceFeedCompressor(priceFeedCompressor);

        // Update all price feeds before running the test
        _updateAllPriceFeeds();

        // Get credit accounts from both implementations
        (CreditAccountData[] memory newCAs,) = cac.getCreditAccounts(
            creditManager,
            CreditAccountFilter({
                owner: address(0),
                minHealthFactor: 0,
                maxHealthFactor: 0,
                includeZeroDebt: true,
                reverting: false
            }),
            0
        );

        CreditAccountDataOld[] memory oldCAs = dc3.getCreditAccountsByCreditManager(creditManager, new PriceUpdate[](0));

        // Compare total number of credit accounts
        assertEq(newCAs.length, oldCAs.length, "Credit accounts length mismatch");

        // Compare credit accounts in order
        for (uint256 k; k < newCAs.length; k++) {
            assertEq(newCAs[k].creditAccount, oldCAs[k].addr, "Credit account address mismatch");
            assertEq(newCAs[k].creditManager, oldCAs[k].creditManager, "Credit manager mismatch");
            assertEq(newCAs[k].creditFacade, oldCAs[k].creditFacade, "Credit facade mismatch");
            assertEq(newCAs[k].underlying, oldCAs[k].underlying, "Underlying mismatch");
            assertEq(newCAs[k].owner, oldCAs[k].borrower, "Owner/borrower mismatch");
            assertEq(newCAs[k].debt, oldCAs[k].debt, "Debt mismatch");
            assertEq(newCAs[k].enabledTokensMask, oldCAs[k].enabledTokensMask, "Enabled tokens mask mismatch");
            assertEq(newCAs[k].accruedInterest, oldCAs[k].accruedInterest, "Accrued interest mismatch");
            assertEq(newCAs[k].accruedFees, oldCAs[k].accruedFees, "Accrued fees mismatch");
            assertEq(newCAs[k].totalDebtUSD, oldCAs[k].totalDebtUSD, "Total debt USD mismatch");
            assertEq(newCAs[k].totalValueUSD, oldCAs[k].totalValueUSD, "Total value USD mismatch");
            assertEq(newCAs[k].twvUSD, oldCAs[k].twvUSD, "TWV USD mismatch");
            assertEq(newCAs[k].healthFactor, oldCAs[k].healthFactor, "Health factor mismatch");
            assertEq(newCAs[k].expirationDate, oldCAs[k].expirationDate, "Expiration date mismatch");

            // Compare only tokens with non-zero balance from new implementation
            for (uint256 m; m < newCAs[k].tokens.length; m++) {
                TokenInfo memory newToken = newCAs[k].tokens[m];

                // Find matching token in old implementation
                bool found = false;
                for (uint256 n; n < oldCAs[k].balances.length; n++) {
                    if (oldCAs[k].balances[n].token == newToken.token) {
                        TokenBalance memory oldToken = oldCAs[k].balances[n];
                        assertEq(newToken.balance, oldToken.balance, "Token balance mismatch");
                        assertEq(newToken.quota, oldToken.quota, "Token quota mismatch");
                        found = true;
                        break;
                    }
                }
                require(found, string.concat("Token not found in old implementation: ", vm.toString(newToken.token)));
            }

            // Verify that any non-zero balance tokens in old implementation are present in new implementation
            for (uint256 n; n < oldCAs[k].balances.length; n++) {
                TokenBalance memory oldToken = oldCAs[k].balances[n];
                if (oldToken.balance > 1) {
                    bool found = false;
                    for (uint256 m; m < newCAs[k].tokens.length; m++) {
                        if (newCAs[k].tokens[m].token == oldToken.token) {
                            found = true;
                            break;
                        }
                    }
                    require(
                        found,
                        string.concat(
                            "Token with non-zero balance not found in new implementation: ", vm.toString(oldToken.token)
                        )
                    );
                }
            }
        }
    }

    function _refreshUpdatablePriceFeed(address priceFeed, bytes32 contractType) internal {
        if (contractType == "PRICE_FEED::REDSTONE") {
            uint256 initialTS = block.timestamp;

            bytes32 dataFeedId = RedstonePriceFeed(priceFeed).dataFeedId();
            uint8 signersThreshold = RedstonePriceFeed(priceFeed).getUniqueSignersThreshold();

            bytes memory payload =
                _getRedstonePayload(bytes32ToString((dataFeedId)), Strings.toString(signersThreshold));

            if (payload.length == 0) return;

            (uint256 expectedPayloadTimestamp,) = abi.decode(payload, (uint256, bytes));

            if (expectedPayloadTimestamp > block.timestamp) {
                vm.warp(expectedPayloadTimestamp);
            }

            try RedstonePriceFeed(priceFeed).updatePrice(payload) {} catch {}

            vm.warp(initialTS);
        } else {
            revert("Unknown updatable price feed type");
        }
    }

    function _getRedstonePayload(string memory dataFeedId, string memory signersThreshold)
        internal
        returns (bytes memory)
    {
        string[2] memory dataServiceIds = ["redstone-primary-prod", "redstone-arbitrum-prod"];

        for (uint256 i = 0; i < dataServiceIds.length; ++i) {
            string[] memory args = new string[](6);
            args[0] = "npx";
            args[1] = "ts-node";
            args[2] = "./scripts/redstone.ts";
            args[3] = dataServiceIds[i];
            args[4] = dataFeedId;
            args[5] = signersThreshold;

            try vm.ffi(args) returns (bytes memory response) {
                return response;
            } catch {}
        }

        return "";
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
