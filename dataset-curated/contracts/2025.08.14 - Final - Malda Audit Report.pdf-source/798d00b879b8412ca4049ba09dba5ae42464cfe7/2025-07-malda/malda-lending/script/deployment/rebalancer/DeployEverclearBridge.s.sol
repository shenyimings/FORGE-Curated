// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EverclearBridge} from "src/rebalancer/bridges/EverclearBridge.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script DeployEverclearBridge  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --sig "run(address,address)" 0x0,0x0 \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployEverclearBridge is Script {
    function run(address roles, address feeAdapter, Deployer deployer) public returns (address) {
        bytes32 salt = getSalt("EverclearBridgeV1.0");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address created =
            deployer.create(salt, abi.encodePacked(type(EverclearBridge).creationCode, abi.encode(roles, feeAdapter)));
        vm.stopBroadcast();

        console.log(" EverclearBridge deployed at: %s", created);
        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
