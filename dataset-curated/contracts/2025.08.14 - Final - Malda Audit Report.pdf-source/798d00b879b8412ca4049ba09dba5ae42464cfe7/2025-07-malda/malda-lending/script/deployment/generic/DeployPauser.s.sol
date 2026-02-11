// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Pauser} from "src/pauser/Pauser.sol";
import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script DeployPauser \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployPauser is Script {
    function run(Deployer deployer, address roles, address operator, address owner) public returns (address) {
        uint256 key = vm.envUint("PRIVATE_KEY");

        bytes32 salt = getSalt("PauserV1.0.0");

        console.log("Deploying Pauser");

        address created = deployer.precompute(salt);

        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created =
                deployer.create(salt, abi.encodePacked(type(Pauser).creationCode, abi.encode(roles, operator, owner)));
            vm.stopBroadcast();
            console.log("Pauser deployed at: %s", created);
        } else {
            console.log("Using existing Pauser at: %s", created);
        }

        // set PAUSE_MANAGER for owner
        // set GUARDIAN_PAUSE for `created`

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
