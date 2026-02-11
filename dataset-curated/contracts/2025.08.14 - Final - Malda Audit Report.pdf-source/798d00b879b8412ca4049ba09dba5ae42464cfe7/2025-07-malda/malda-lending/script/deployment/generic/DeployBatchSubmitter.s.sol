// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DeployBase} from "script/deployers/DeployBase.sol";
import {BatchSubmitter} from "src/mToken/BatchSubmitter.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script DeployBatchSubmitter  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run(address,address)" 0x0 0x0\
 *     --broadcast
 */
contract DeployBatchSubmitter is Script {
    function run(Deployer deployer, address roles, address zkVerifier, address owner) public returns (address) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        bytes32 salt = getSalt("BatchSubmitterV1.0.0");

        address created = deployer.precompute(salt);
        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created = deployer.create(
                salt, abi.encodePacked(type(BatchSubmitter).creationCode, abi.encode(roles, zkVerifier, owner))
            );
            vm.stopBroadcast();
            console.log("BatchSubmitter deployed at:", created);
        } else {
            console.log("Using existing BatchSubmitter at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
