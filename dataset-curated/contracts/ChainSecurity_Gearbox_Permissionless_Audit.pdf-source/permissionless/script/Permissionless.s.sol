// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script, console2} from "forge-std/Script.sol";

import {CCGHelper} from "../contracts/test/helpers/CCGHelper.sol";
import {GlobalSetup} from "../contracts/test/helpers/GlobalSetup.sol";

contract PermissionlessScript is Script, GlobalSetup {
    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        _fundActors();

        _setUpGlobalContracts();

        console2.log("DONE");
        vm.stopBroadcast();

        // Store address manager state as JSON
        string memory json = vm.serializeAddress("addresses", "instanceManager", address(instanceManager));
        json = vm.serializeAddress("addresses", "bytecodeRepository", address(bytecodeRepository));
        json = vm.serializeAddress("addresses", "multisig", address(multisig));
        json = vm.serializeAddress("addresses", "addressProvider", address(instanceManager.addressProvider()));

        vm.writeJson(json, "./addresses.json");
    }

    function _fundActors() internal {
        address[6] memory actors = [instanceOwner, author, dao, auditor, signer1, signer2];
        for (uint256 i = 0; i < actors.length; ++i) {
            payable(actors[i]).transfer(10 ether);
        }
    }
}
