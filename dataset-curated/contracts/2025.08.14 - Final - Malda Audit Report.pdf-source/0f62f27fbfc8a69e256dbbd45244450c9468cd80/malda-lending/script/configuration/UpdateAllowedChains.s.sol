// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {mErc20Host} from "../../src/mToken/host/mErc20Host.sol";
import {Script, console} from "forge-std/Script.sol";

contract UpdateAllowedChains is Script {
    function run(address market, uint32 chainId, bool isAllowed) public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        console.log("Updating allowed chain for market %s", market);

        if (mErc20Host(market).allowedChains(chainId) == isAllowed) {
            console.log("Allowed chain already set");
            return;
        }

        vm.startBroadcast(key);
        mErc20Host(market).updateAllowedChain(chainId, isAllowed);
        vm.stopBroadcast();

        console.log("Allowed chain updated for market %s", market);
    }
}
