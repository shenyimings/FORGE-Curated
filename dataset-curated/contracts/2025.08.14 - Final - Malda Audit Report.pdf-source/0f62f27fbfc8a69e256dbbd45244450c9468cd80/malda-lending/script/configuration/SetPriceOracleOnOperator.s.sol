// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Operator} from "src/Operator/Operator.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetPriceOracleOnOperator is Script {
    function run(address oracle) public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(key);

        address operator = vm.envAddress("OPERATOR");
        Operator(operator).setPriceOracle(oracle);

        console.log(" Updated price oracle on operator: %s", oracle);

        vm.stopBroadcast();
    }
}
