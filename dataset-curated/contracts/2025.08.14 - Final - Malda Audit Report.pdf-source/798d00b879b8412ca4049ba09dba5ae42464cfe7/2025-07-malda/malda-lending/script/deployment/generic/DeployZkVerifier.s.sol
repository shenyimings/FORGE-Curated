// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {ZkVerifier} from "src/verifier/ZkVerifier.sol";
import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";

contract DeployZkVerifier is Script {
    function run(Deployer _deployer, address owner, address verifier, bytes32 imageId) public returns (address) {
        bytes32 salt = getSalt("ZkVerifier1.0.0");

        console.log("Deploying ZkVerifier");

        address created = _deployer.precompute(salt);
        if (created.code.length == 0) {
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            created = _deployer.create(
                salt, abi.encodePacked(type(ZkVerifier).creationCode, abi.encode(owner, imageId, verifier))
            );
            vm.stopBroadcast();
            console.log("ZkVerifier deployed at: %s", created);
        } else {
            console.log("Using existing ZkVerifier at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
