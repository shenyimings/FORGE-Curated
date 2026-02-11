// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import {CCIPProver} from "../contracts/prover/CCIPProver.sol";
import {ICreate3Deployer} from "../contracts/tools/ICreate3Deployer.sol";
import {AddressConverter} from "../contracts/libs/AddressConverter.sol";

/**
 * @title DeployCCIPProver
 * @notice Script to deploy CCIPProver using CREATE3 for deterministic cross-chain addresses
 * @dev The deployed prover will whitelist its own address, allowing it to receive messages
 *      from the same prover address on other chains
 */
contract DeployCCIPProver is Script {
    using AddressConverter for address;

    function run() external {
        // Load environment variables
        address portal = vm.envAddress("PORTAL_CONTRACT");
        bytes32 salt = vm.envBytes32("SALT");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Determine CCIP Router based on chain ID
        uint256 chainId = block.chainid;
        address ccipRouter;

        if (chainId == 10) {
            // Optimism
            ccipRouter = 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f;
        } else if (chainId == 8453) {
            // Base
            ccipRouter = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
        } else if (chainId == 1) {
            // Ethereum
            ccipRouter = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
        } else if (chainId == 2020) {
            // Ronin
            ccipRouter = 0x46527571D5D1B68eE7Eb60B18A32e6C60DcEAf99;
        } else {
            revert("Unsupported chain ID");
        }

        // Configuration
        address create3Deployer = 0xC6BAd1EbAF366288dA6FB5689119eDd695a66814;
        uint256 minGasLimit = 200000;

        console.log("=== CCIPProver Deployment Configuration ===");
        console.log("Chain ID:", chainId);
        console.log("CCIP Router:", ccipRouter);
        console.log("Portal:", portal);
        console.log("CREATE3 Deployer:", create3Deployer);
        console.log("Salt:", vm.toString(salt));
        console.log("Min Gas Limit:", minGasLimit);
        console.log("");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);

        // Step 1: Predict the deployed address
        bytes memory creationCode = type(CCIPProver).creationCode;
        address predictedAddress = ICreate3Deployer(create3Deployer).deployedAddress(
            creationCode,
            deployer,
            salt
        );

        console.log("Predicted CCIPProver address:", predictedAddress);

        // Step 2: Create provers whitelist with only the predicted address
        bytes32[] memory provers = new bytes32[](1);
        provers[0] = predictedAddress.toBytes32();

        console.log("Provers whitelist:");
        console.log("  [0]:", vm.toString(provers[0]));
        console.log("");

        // Step 3: Encode constructor arguments
        bytes memory constructorArgs = abi.encode(
            ccipRouter,
            portal,
            provers,
            minGasLimit
        );

        // Step 4: Combine creation code with constructor arguments
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);

        console.log("Deploying CCIPProver via CREATE3...");

        // Step 5: Deploy using CREATE3
        address deployedAddress = ICreate3Deployer(create3Deployer).deploy(
            bytecode,
            salt
        );

        vm.stopBroadcast();

        // Verify deployment
        require(deployedAddress == predictedAddress, "Deployed address mismatch");

        console.log("");
        console.log("=== Deployment Successful ===");
        console.log("CCIPProver deployed at:", deployedAddress);
        console.log("Proof Type:", CCIPProver(deployedAddress).getProofType());
        console.log("Router:", CCIPProver(deployedAddress).ROUTER());
        console.log("Min Gas Limit:", CCIPProver(deployedAddress).MIN_GAS_LIMIT());
        console.log("Whitelist Size:", CCIPProver(deployedAddress).getWhitelistSize());

        // Verify the prover whitelisted itself
        require(
            CCIPProver(deployedAddress).isWhitelisted(deployedAddress.toBytes32()),
            "Self-whitelisting verification failed"
        );
        console.log("Self-whitelisting: VERIFIED");
    }
}
