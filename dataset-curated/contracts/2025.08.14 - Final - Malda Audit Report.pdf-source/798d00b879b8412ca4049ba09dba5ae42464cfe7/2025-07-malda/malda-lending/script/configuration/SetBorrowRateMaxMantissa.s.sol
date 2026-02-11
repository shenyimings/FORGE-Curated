// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {mTokenConfiguration} from "../../src/mToken/mTokenConfiguration.sol";

import {Script, console} from "forge-std/Script.sol";

contract SetBorrowRateMaxMantissa is Script {
    function run(address market, uint256 borrowRateMaxMantissa) public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        console.log("Setting borrow rate max mantissa for market", market);

        if (mTokenConfiguration(market).borrowRateMaxMantissa() == borrowRateMaxMantissa) {
            console.log("Borrow rate max mantissa already set");
            return;
        }

        vm.startBroadcast(key);
        mTokenConfiguration(market).setBorrowRateMaxMantissa(borrowRateMaxMantissa);
        vm.stopBroadcast();

        console.log("Set borrow rate max mantissa for market", market);
    }
}
