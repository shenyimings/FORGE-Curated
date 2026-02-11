// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {mErc20Host} from "../../src/mToken/host/mErc20Host.sol";
import {Script, console} from "forge-std/Script.sol";

contract UpdateAllAllowedChains is Script {
    function run() public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        bool isAllowed = true;

        address[] memory lineaAndEthMarkets = new address[](8);
        lineaAndEthMarkets[0] = 0x269C36A173D881720544Fb303E681370158FF1FD;
        lineaAndEthMarkets[1] = 0xC7Bc6bD45Eb84D594f51cED3c5497E6812C7732f;
        lineaAndEthMarkets[2] = 0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90;
        lineaAndEthMarkets[3] = 0x2B588F7f4832561e46924F3Ea54C244569724915;
        lineaAndEthMarkets[4] = 0x1D8e8cEFEb085f3211Ab6a443Ad9051b54D1cd1a;
        lineaAndEthMarkets[5] = 0x0B3c6645F4F2442AD4bbee2e2273A250461cA6f8;
        lineaAndEthMarkets[6] = 0x8BaD0c523516262a439197736fFf982F5E0987cC;
        lineaAndEthMarkets[7] = 0x4DF3DD62DB219C47F6a7CB1bE02C511AFceAdf5E;

        uint32[] memory chains = new uint32[](2);
        chains[0] = 1;
        //chains[1] = 59144;
        chains[1] = 8453;
        
        for(uint256 i; i < lineaAndEthMarkets.length; i++) {
            address market = lineaAndEthMarkets[i];
            for (uint256 j; j < chains.length; j++) {
                uint32 chainId = chains[j];
                if (mErc20Host(market).allowedChains(chainId) == isAllowed) {
                    console.log("Allowed chain already set");
                    continue;
                }

                vm.startBroadcast(key);
                mErc20Host(market).updateAllowedChain(chainId, isAllowed);
                vm.stopBroadcast();
                console.log("Allowed chain updated for market %s", market);
            }
        }

    }
}
