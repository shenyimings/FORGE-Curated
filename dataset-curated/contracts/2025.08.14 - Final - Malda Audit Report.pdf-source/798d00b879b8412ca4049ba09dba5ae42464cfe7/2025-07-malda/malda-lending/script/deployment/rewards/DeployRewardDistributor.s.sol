// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {RewardDistributor} from "src/rewards/RewardDistributor.sol";
import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * forge script DeployRewardDistributor  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployRewardDistributor is Script {
    function run(Deployer deployer, address owner) public returns (address) {
        uint256 key = vm.envUint("PRIVATE_KEY");

        bytes32 implSalt = getSalt("RewardDistributorV1.0.0");
        address implementation = deployer.precompute(implSalt);
        if (implementation.code.length > 0) {
            console.log("RewardDistributor implementation already deployed at: %s", implementation);
        } else {
            vm.startBroadcast(key);
            implementation = deployer.create(implSalt, type(RewardDistributor).creationCode);
            vm.stopBroadcast();
            console.log("RewardDistributor implementation deployed at: %s", implementation);
        }

        bytes memory initData = abi.encodeWithSelector(RewardDistributor.initialize.selector, owner);
        // Deploy proxy
        bytes32 proxySalt = getSalt("RewardDistributorV1.0.0 Proxy");
        address proxy = deployer.precompute(proxySalt);
        if (proxy.code.length > 0) {
            console.log("RewardDistributor proxy already deployed at: %s", proxy);
        } else {
            vm.startBroadcast(key);
            proxy = deployer.create(
                proxySalt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, owner, initData)
                )
            );
            vm.stopBroadcast();
            console.log("RewardDistributor deployed at: %s", proxy);
        }

        return proxy;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
