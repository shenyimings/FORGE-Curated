// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Permit3ApproverModule } from "../src/modules/Permit3ApproverModule.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract DeployModule is Script {
    address public constant CREATE2_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    
    // Default Permit3 address (can be overridden via env)
    address public constant DEFAULT_PERMIT3 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        // Get Permit3 address from environment or use default
        address permit3 = vm.envOr("PERMIT3_ADDRESS", DEFAULT_PERMIT3);
        bytes32 salt = vm.envOr("SALT", bytes32(0));
        
        console.log("Deploying Permit3ApproverModule with:");
        console.log("  Permit3:", permit3);
        console.log("  Salt:", vm.toString(salt));

        vm.startBroadcast();

        // Option 1: Direct deployment
        Permit3ApproverModule module = new Permit3ApproverModule(permit3);
        console.log("Permit3ApproverModule deployed at:", address(module));

        vm.stopBroadcast();
    }

    function runDeterministic() external {
        // Get Permit3 address from environment or use default
        address permit3 = vm.envOr("PERMIT3_ADDRESS", DEFAULT_PERMIT3);
        bytes32 salt = vm.envOr("SALT", keccak256("Permit3ApproverModule"));
        
        console.log("Deploying Permit3ApproverModule with CREATE2:");
        console.log("  Permit3:", permit3);
        console.log("  Salt:", vm.toString(salt));

        vm.startBroadcast();

        // Deploy using CREATE2 for deterministic addresses
        address moduleAddress = deployWithCreate2(permit3, salt);
        console.log("Permit3ApproverModule deployed at:", moduleAddress);

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the module using CREATE2 factory
     * @param permit3 Address of the Permit3 contract
     * @param salt Unique salt for deterministic address generation
     * @return moduleAddress The address of the deployed module
     */
    function deployWithCreate2(address permit3, bytes32 salt) internal returns (address moduleAddress) {
        bytes memory initCode = abi.encodePacked(
            type(Permit3ApproverModule).creationCode,
            abi.encode(permit3)
        );

        // Call CREATE2 factory
        bytes4 selector = bytes4(keccak256("deploy(bytes,bytes32)"));
        bytes memory data = abi.encodePacked(selector, abi.encode(initCode, salt));
        
        (bool success, bytes memory returnData) = CREATE2_FACTORY.call(data);
        require(success, "Failed to deploy module via CREATE2");
        
        moduleAddress = abi.decode(returnData, (address));
    }

    /**
     * @notice Compute the deterministic address for the module
     * @param permit3 Address of the Permit3 contract
     * @param salt Deployment salt
     * @return The computed address
     */
    function computeAddress(address permit3, bytes32 salt) external pure returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(Permit3ApproverModule).creationCode,
            abi.encode(permit3)
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                CREATE2_FACTORY,
                salt,
                keccak256(initCode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }
}