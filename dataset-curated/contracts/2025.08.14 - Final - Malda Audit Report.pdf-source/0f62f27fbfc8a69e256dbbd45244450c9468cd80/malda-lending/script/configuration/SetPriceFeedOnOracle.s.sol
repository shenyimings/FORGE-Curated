// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MixedPriceOracleV3} from "src/oracles/MixedPriceOracleV3.sol";
import {IDefaultAdapter} from "src/interfaces/IDefaultAdapter.sol";

/**
 * forge script SetPriceFeedOnOracle  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run(string,address,string,uint8)" "WETHUSD" "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419" "USD" 18 \
 *     --broadcast
 */
contract SetPriceFeedOnOracle is Script {
    function run(string memory symbol, address priceFeed, string memory toSymbol, uint8 underlyingDecimals) public {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        address oracle = vm.envAddress("ORACLE");

        IDefaultAdapter.PriceConfig memory config = IDefaultAdapter.PriceConfig({
            defaultFeed: priceFeed,
            toSymbol: toSymbol,
            underlyingDecimals: underlyingDecimals
        });

        vm.startBroadcast(key);
        MixedPriceOracleV3(oracle).setConfig(symbol, config);
        vm.stopBroadcast();

        console.log("Set price feed for %s on oracle %s:", symbol, oracle);
        console.log(" - Price Feed: %s", priceFeed);
        console.log(" - To Symbol: %s", toSymbol);
        console.log(" - Underlying Decimals: %d", underlyingDecimals);
    }
}
