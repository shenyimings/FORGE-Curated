// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Operator} from "src/Operator/Operator.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {Script, console} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * forge script script/deployment/markets/DeployOperator.s.sol:DeployOperator  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run(address,address,address)" 0x0,0x0,0x0 \
 *     --broadcast
 */
contract DeployOperator is Script {
    function run(Deployer deployer, address oracle, address rewards, address roles, address owner)
        public
        returns (address)
    {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        bytes32 implSalt = _getSalt("OperatorImplementationV1.0.0");
        address implementation = deployer.precompute(implSalt);
        if (implementation.code.length > 0) {
            console.log("Operator implementation already deployed at:", implementation);
        } else {
            vm.startBroadcast(key);
            implementation = deployer.create(implSalt, abi.encodePacked(type(Operator).creationCode));
            vm.stopBroadcast();
            console.log("Operator implementation deployed at:", implementation);
        }

        bytes memory initData = abi.encodeWithSelector(Operator.initialize.selector, roles, rewards, owner);

        // Deploy proxy
        bytes32 proxySalt = _getSalt("OperatorProxyV1.0.0");
        address operatorAddress = deployer.precompute(proxySalt);
        if (operatorAddress.code.length > 0) {
            console.log("Operator proxy already deployed at:", operatorAddress);
        } else {
            vm.startBroadcast(key);
            operatorAddress = deployer.create(
                proxySalt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, owner, initData)
                )
            );
            vm.stopBroadcast();
            console.log("Operator proxy deployed at:", operatorAddress);

            console.log("Setting oracle: ", oracle);
            vm.startBroadcast(key);
            Operator(operatorAddress).setPriceOracle(oracle);
            vm.stopBroadcast();
            console.log("Oracle has been set");
        }
      
        return operatorAddress;
    }

    function _getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
