// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {ZkVerifier} from "src/verifier/ZkVerifier.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetZkImageId is Script {
    function run(address zkVerifier, bytes32 imageId) public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        console.log("Setting ZK image ID for IZkVerifier %s", zkVerifier);

        if (ZkVerifier(zkVerifier).imageId() == imageId) {
            console.log("ZK image ID already set");
            return;
        }

        vm.startBroadcast(key);
        ZkVerifier(zkVerifier).setImageId(imageId);
        vm.stopBroadcast();
    }
}
