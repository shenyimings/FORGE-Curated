// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {LikwidHelper} from "../test/utils/LikwidHelper.sol";

contract DeployHelperScript is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    error ManagerNotExist();

    LikwidHelper helper;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address owner = msg.sender;
        console.log("owner:", owner);
        address sender = msg.sender;
        console.log("sender:", sender);

        IVault vault = IVault(0xC2107542bF154290934f3639452A3dd0C6077DcB);
        console.log("vault:", address(vault));

        helper = new LikwidHelper(owner, vault);
        console.log("helper:", address(helper));

        vm.stopBroadcast();
    }
}
