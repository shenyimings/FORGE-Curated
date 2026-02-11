// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Roles} from "src/Roles.sol";
import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {DefaultGasHelper} from "src/oracles/gas/DefaultGasHelper.sol";

/**
 * forge script script/deployment/generic/DeploGasHelper.s.sol:DeploGasHelper \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployGasHelper is Script {
    function run(Deployer _deployer, address owner) public returns (address) {
        bytes32 salt = getSalt("GasHelperV1.0.0");

        console.log("Deploying GasHelper");

        address created = _deployer.precompute(salt);
        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            created = _deployer.create(salt, abi.encodePacked(type(DefaultGasHelper).creationCode, abi.encode(owner)));
            vm.stopBroadcast();
            console.log("GasHelper deployed at: %s", created);
        } else {
            console.log("Using existing GasHelper at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
