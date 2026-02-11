// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";

/**
 * forge script script/deployers/Deployer.s.sol:DeployerScript \
 *     --sig "run(uint32,address)" 59141 0xCde13fF278bc484a09aDb69ea1eEd3cAf6Ea4E00 \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployDeployer is Script {
    function run(uint32 expectedChainId, address owner, string memory salt) public returns (address) {
        _verifyChain(expectedChainId);

        bytes32 _salt = getSalt(salt);

        // Compute the deterministic address first
        bytes memory bytecode = type(Deployer).creationCode;
        bytes memory constructorArgs = abi.encode(owner);
        bytes memory bytecodeWithConstructor = abi.encodePacked(bytecode, constructorArgs);
        address deployerAddress = _computeCreate2Address(_salt, bytecodeWithConstructor);
        deployerAddress = 0xc781BaD08968E324D1B91Be3cca30fAd86E7BF98;
        // Deploy only if not already deployed
        if (deployerAddress.code.length == 0) {
            console.log("Deploying deployer. Nothing found on", deployerAddress);
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
            deployerAddress = _deployCreate2(_salt, owner);
            vm.stopBroadcast();
            console.log("Deployer contract deployed at: %s", deployerAddress);
        } else {
            console.log("Using existing deployer at: %s", deployerAddress);
        }

        return deployerAddress;
    }

    function _computeCreate2Address(bytes32 salt, bytes memory bytecodeWithConstructor)
        internal
        view
        returns (address)
    {
        bytes32 bytecodeHash = keccak256(bytecodeWithConstructor);
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(_data)));
    }

    function _deployCreate2(bytes32 salt, address owner) internal returns (address) {
        Deployer deployer = new Deployer{salt: salt}(owner);
        return address(deployer);
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }

    function _verifyChain(uint32 expectedChainId) internal view {
        require(block.chainid == expectedChainId, "Wrong chain");
    }
}
