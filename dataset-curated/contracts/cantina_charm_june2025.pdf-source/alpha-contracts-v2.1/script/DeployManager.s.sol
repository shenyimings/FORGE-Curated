// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/Script.sol";
import {AlphaProPeriphery} from "../contracts/AlphaProPeriphery.sol";
import {Constants} from "../test/Constants.sol";

contract DeployManagerScript is Script, Test {
    function run() external {
        uint256 deployerPK = vm.envUint("PK_DEPLOYER");

        vm.startBroadcast(deployerPK);
        AlphaProPeriphery alphaProPeriphery = new AlphaProPeriphery();
        vm.stopBroadcast();

        emit log_string("Successfully deployed");
        emit log_named_address("alphaProPeriphery", address(alphaProPeriphery));
    }
}
