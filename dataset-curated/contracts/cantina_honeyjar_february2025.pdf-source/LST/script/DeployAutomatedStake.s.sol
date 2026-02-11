// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/automatedStake.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";

contract DeployAutomatedStake is Script {
    // Configuration from index.ts
    address constant FAT_BERA_ADDRESS = 0xBAE11292A3E693aF73651BDa350D752AE4A391D4;
    address constant W_BERA_ADDRESS = 0x6969696969696969696969696969696969696969;
    address constant BEACON_DEPOSIT_CONTRACT = 0x4242424242424242424242424242424242424242;

    // Validator parameters from index.ts (original values)
    bytes constant VALIDATOR_PUBKEY =
        hex"a0c673180d97213c1c35fe3bf4e684dd3534baab235a106d1f71b9c8a37e4d37a056d47546964fd075501dff7f76aeaf";
    bytes constant WITHDRAWAL_CREDENTIALS = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes constant VALIDATOR_SIGNATURE =
        hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    // Additional validator pubkeys
    bytes constant VALIDATOR_PUBKEY_2 =
        hex"89cbd542c737cca4bc33f1ea5084a857a7620042fe37fd326ecf5aeb61f2ce096043cd0ed57ba44693cf606978b566ba";
    bytes constant VALIDATOR_PUBKEY_3 =
        hex"b82a791d7c3d72efa6759e0250785346266d6c70ed881424ec63ad4d060904983bc57903fa133a9bc00c2d6f9b12964d";

    // Addresses from user request
    address constant MULTISIG_ADDRESS = 0xE6644e0b941A03Af8ff10BDB185d5E74D520270e;
    address constant VALIDATOR_OPERATOR_ADDRESS = 0x0000000000000000000000000000000000000000;
    address constant AUTO_STAKE_CALLER = 0x87201fe7df215E7125ba8F32443a82923f6A2707;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Create an array of validators with three validators
        AutomatedStake.Validator[] memory initialValidators = new AutomatedStake.Validator[](3);

        // Initialize with the original validator
        initialValidators[0] = AutomatedStake.Validator({
            pubkey: VALIDATOR_PUBKEY,
            withdrawalCredentials: WITHDRAWAL_CREDENTIALS,
            signature: VALIDATOR_SIGNATURE,
            operator: VALIDATOR_OPERATOR_ADDRESS
        });

        // Add second validator with the same credentials except pubkey
        initialValidators[1] = AutomatedStake.Validator({
            pubkey: VALIDATOR_PUBKEY_2,
            withdrawalCredentials: WITHDRAWAL_CREDENTIALS,
            signature: VALIDATOR_SIGNATURE,
            operator: VALIDATOR_OPERATOR_ADDRESS
        });

        // Add third validator with the same credentials except pubkey
        initialValidators[2] = AutomatedStake.Validator({
            pubkey: VALIDATOR_PUBKEY_3,
            withdrawalCredentials: WITHDRAWAL_CREDENTIALS,
            signature: VALIDATOR_SIGNATURE,
            operator: VALIDATOR_OPERATOR_ADDRESS
        });

        bytes memory initData = abi.encodeWithSelector(
            AutomatedStake.initialize.selector,
            FAT_BERA_ADDRESS,
            W_BERA_ADDRESS,
            BEACON_DEPOSIT_CONTRACT,
            initialValidators,
            MULTISIG_ADDRESS,
            AUTO_STAKE_CALLER
        );

        address proxy = Upgrades.deployUUPSProxy("automatedStake.sol:AutomatedStake", initData);

        vm.stopBroadcast();

        console.log("AutomatedStake proxy deployed to: %s", proxy);
        console.log("Implementation deployed at: %s", Upgrades.getImplementationAddress(proxy));
        console.log("Admin role granted to: %s", MULTISIG_ADDRESS);
        console.log("Staker role granted to: %s", AUTO_STAKE_CALLER);
        console.log("Number of validators initialized: 3");
        console.log("FatBERA address set to: %s", FAT_BERA_ADDRESS);
        console.log("WBERA address set to: %s", W_BERA_ADDRESS);
        console.log("Beacon deposit contract set to: %s", BEACON_DEPOSIT_CONTRACT);

        // Log validator information
        console.log("");
        console.log("Validator Information:");
        console.log("Validator 0 pubkey: (bytes value, see VALIDATOR_PUBKEY)");
        console.log("Validator 1 pubkey: (bytes value, see VALIDATOR_PUBKEY_2)");
        console.log("Validator 2 pubkey: (bytes value, see VALIDATOR_PUBKEY_3)");
        console.log("Withdrawal credentials: (bytes value, see constants)");
        console.log("Validator operator address: %s", VALIDATOR_OPERATOR_ADDRESS);
        console.log("Minimum stake amount: 15,000 WBERA");
    }
}
