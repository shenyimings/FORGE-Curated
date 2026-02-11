// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "../contracts/DIAWhitelistedStaking.sol";
import "../contracts/DIAExternalStaking.sol";

/// @title GenerateWallets
/// @notice Script to generate wallets, add them to whitelist, and transfer contract ownership
/// @dev This script performs three main operations:
///      1. Generates 10 wallets and adds them to the whitelist
///      2. Generates a new owner wallet
///      3. Transfers ownership of both staking contracts to the new owner
contract GenerateWallets is Script {
    function run() external {
        /*
          DIAExternalStaking deployed to: 0xA56B1c5F3738F3B03722d7e7187907a610781D4E
  DIAWhitelistedStaking deployed to: 0x45a22016e5060dc277D4a251E5425a291d8A3665

        */
        // Get the contract addresses
        address whitelistedStakingAddress = 0x8Ec7ebB41230e34448569EF6b868e88989244A14;
        address externalStakingAddress = 0x9b8bE24f9aE64ae54aCf47e7e3A2860c89297C53;
        
        DIAWhitelistedStaking whitelistedStaking = DIAWhitelistedStaking(whitelistedStakingAddress);
        DIAExternalStaking externalStaking = DIAExternalStaking(externalStakingAddress);

        // Generate and print 10 wallets
        for (uint256 i = 0; i < 10; i++) {
            // Generate a new private key
            uint256 privateKey = uint256(keccak256(abi.encodePacked(block.timestamp, i)));
            address publicKey = vm.addr(privateKey);

            // Print wallet info
            console.log("\nWallet %d:", i + 1);
            console.log("Private Key:", vm.toString(privateKey));
            console.log("Public Key:", publicKey);

            // Add to whitelist
            vm.startBroadcast();
            try whitelistedStaking.addWhitelistedStaker(publicKey) {
                console.log("Added to whitelist");
            } catch {
                console.log("Failed to add to whitelist - continuing...");
            }
            vm.stopBroadcast();
        }

        // Generate two additional keys for ownership transfer
        uint256 newOwnerPrivateKey = uint256(keccak256(abi.encodePacked(block.timestamp, "new_owner")));
        address newOwnerPublicKey = vm.addr(newOwnerPrivateKey);

        uint256 backupOwnerPrivateKey = uint256(keccak256(abi.encodePacked(block.timestamp, "backup_owner")));
        address backupOwnerPublicKey = vm.addr(backupOwnerPrivateKey);

        // Print new owner keys
        console.log("\nNew Owner Wallet:");
        console.log("Private Key:", vm.toString(newOwnerPrivateKey));
        console.log("Public Key:", newOwnerPublicKey);

        // Print backup owner keys
        // console.log("\nBackup Owner Wallet:");
        // console.log("Private Key:", vm.toString(backupOwnerPrivateKey));
        // console.log("Public Key:", backupOwnerPublicKey);

        // Transfer ownership of both contracts to new owner
        vm.startBroadcast();
        try whitelistedStaking.transferOwnership(newOwnerPublicKey) {
            console.log("WhitelistedStaking ownership transferred successfully");
        } catch {
            console.log("Failed to transfer WhitelistedStaking ownership - continuing...");
        }

        try externalStaking.transferOwnership(newOwnerPublicKey) {
            console.log("ExternalStaking ownership transferred successfully");
        } catch {
            console.log("Failed to transfer ExternalStaking ownership - continuing...");
        }
        vm.stopBroadcast();

        console.log("\nScript completed");
    }
} 