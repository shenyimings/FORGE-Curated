// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract PrepareUpgrade is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        Options memory opts;
        opts.referenceContract = "StakedFatBERAV2.sol:StakedFatBERAV2";

        address impl = Upgrades.prepareUpgrade("StakedFatBERAV3.sol:StakedFatBERAV3", opts);
        console2.log("New V3 implementation:", impl);

        vm.stopBroadcast();
    }
}