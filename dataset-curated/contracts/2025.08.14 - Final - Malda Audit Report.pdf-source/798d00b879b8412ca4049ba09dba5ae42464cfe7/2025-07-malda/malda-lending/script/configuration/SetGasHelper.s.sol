// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {mErc20Host} from "../../src/mToken/host/mErc20Host.sol";
import {Script} from "forge-std/Script.sol";

contract SetGasHelper is Script {
    function run(address market, address gasHelper) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(key);
        mErc20Host(market).setGasHelper(gasHelper);
        vm.stopBroadcast();
    }
}
