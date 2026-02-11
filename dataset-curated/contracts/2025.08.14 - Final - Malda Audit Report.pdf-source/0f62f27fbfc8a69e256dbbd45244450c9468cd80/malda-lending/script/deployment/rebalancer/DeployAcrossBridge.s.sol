// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AccrossBridge} from "src/rebalancer/bridges/AcrossBridge.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script DeployAcrossBridge  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --sig "run(address,address)" 0x0,0x0 \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployAcrossBridge is Script {
    function run(address roles, address spoke, Deployer deployer) public returns (address) {
        bytes32 salt = getSalt("AcrossBridgeV1.0");

        vm.startBroadcast(vm.envUint("OWNER_PRIVATE_KEY"));
        address created =
            deployer.create(salt, abi.encodePacked(type(AccrossBridge).creationCode, abi.encode(roles, spoke)));
        vm.stopBroadcast();

        console.log(" AccrossBridge deployed at: %s", created);
        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
