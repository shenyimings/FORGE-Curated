// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MixedPriceOracleV4} from "src/oracles/MixedPriceOracleV4.sol";

/**
 * forge script SetPriceFeedOnOracleV4.  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run(string,address,string,uint8)" "WETHUSD" "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419" "USD" 18 \
 *     --broadcast
 */
contract SetPriceFeedOnOracleV4 is Script {
    //function run(string memory symbol, address priceFeed, string memory toSymbol, uint8 underlyingDecimals) public {
    function run() public {
        string memory symbol = "mweETH";
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        MixedPriceOracleV4.PriceConfig memory config = MixedPriceOracleV4.PriceConfig({
            api3Feed: 0x6Bd45e0f0adaAE6481f2B4F3b867911BF5f8321b,
            eOracleFeed: 0xb71B0D0Bf654D360E5CD5B39E8bbD7CEE9970E09,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        vm.startBroadcast(key);
        MixedPriceOracleV4(0x16f8668d7d650b494861569279E4F48D29C90fbD).setConfig(symbol, config);
        vm.stopBroadcast();
    }
}
