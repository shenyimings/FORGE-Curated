// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {LiquidationHelper} from "src/utils/LiquidationHelper.sol";
import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script script/deployment/generic/DeployLiquidationHelper.s.sol:DeployLiquidationHelper \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployLiquidationHelper is Script {
    function run(Deployer _deployer) public returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes("LiquidationHelperV1.0.0"))
        );

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address created = _deployer.create(salt, type(LiquidationHelper).creationCode);
        vm.stopBroadcast();

        console.log("LiquidationHelper deployed at: %s", created);

        return created;
    }
}
