// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/Script.sol";
import {ManagerStore} from "../contracts/ManagerStore.sol";
import {Constants} from "../test/Constants.sol";

contract DeployPeripheryScript is Script, Test {
    function run() external {
        uint256 deployerPK = vm.envUint("PK_DEPLOYER");
        address deployerAddr = vm.addr(deployerPK);

        if (block.chainid != 137) {
            emit log_named_uint(
                "Skipping ManagerStore contract since deployment chain is not Polygon (137), current chain id",
                block.chainid
            );
        }

        vm.startBroadcast(deployerPK);
        ManagerStore managerStore = new ManagerStore();
        vm.stopBroadcast();

        emit log_string("Successfully deployed");
        emit log_named_address("managerStore", address(managerStore));
    }
}
