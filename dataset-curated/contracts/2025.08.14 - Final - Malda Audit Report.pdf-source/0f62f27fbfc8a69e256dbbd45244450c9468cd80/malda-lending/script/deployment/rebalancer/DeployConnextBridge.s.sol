// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ConnextBridge} from "src/rebalancer/bridges/ConnextBridge.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script DeployConnextBridge  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --sig "run(address,address)" 0x0,0x0 \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployConnextBridge is Script {
    function run(address roles, address connext, Deployer deployer) public returns (address) {
        bytes32 salt = getSalt("ConnextBridgeV1.0");

        vm.startBroadcast(vm.envUint("OWNER_PRIVATE_KEY"));
        address created =
            deployer.create(salt, abi.encodePacked(type(ConnextBridge).creationCode, abi.encode(roles, connext)));
        vm.stopBroadcast();

        console.log(" ConnextBridge deployed at: %s", created);
        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
