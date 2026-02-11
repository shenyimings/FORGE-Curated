// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Flywheel} from "../src/Flywheel.sol";

contract EncodePayout is Script {
    function run() external {
        Flywheel.Payout memory payout =
            Flywheel.Payout({recipient: 0x0BFc799dF7e440b7C88cC2454f12C58f8a29D986, amount: 1e6, extraData: ""});
        console.logBytes(abi.encode(payout));
    }
}
