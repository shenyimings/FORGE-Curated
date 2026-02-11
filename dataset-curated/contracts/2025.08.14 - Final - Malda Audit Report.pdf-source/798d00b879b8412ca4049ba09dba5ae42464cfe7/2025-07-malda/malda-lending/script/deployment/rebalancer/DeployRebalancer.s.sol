// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Rebalancer} from "src/rebalancer/Rebalancer.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script DeployRebalancer  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --sig "run(address)" 0x0 \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployRebalancer is Script {
    function run(address roles, address saveAddress, Deployer deployer) public returns (address) {
        //function run() public returns (address) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        bytes32 salt = getSalt("RebalancerV1.0");

        //address roles = 0x3dc52279175EE96b6A60f6870ec4DfA417c916E3;
        //address saveAddress = 0xCde13fF278bc484a09aDb69ea1eEd3cAf6Ea4E00;
        //Deployer deployer = Deployer(payable(0x7775C52aeA3780944aE69b389c23c9de325ce29B));

        address created = deployer.precompute(salt);
        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created =
                deployer.create(salt, abi.encodePacked(type(Rebalancer).creationCode, abi.encode(roles, saveAddress)));
            vm.stopBroadcast();
            console.log("Rebalancer deployed at:", created);
        } else {
            console.log("Using existing Rebalancer at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
