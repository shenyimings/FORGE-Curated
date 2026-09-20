// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import { GovernanceControllerOApp } from "../contracts/GovernanceControllerOApp.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract SendRawBytesScript is Script {
    using OptionsBuilder for bytes;

    function run(uint32 dstEid) external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the GovernanceControllerOApp address from environment
        address governanceControllerAddress = vm.envAddress("GOVERNANCE_CONTROLLER_ADDRESS");
        GovernanceControllerOApp governanceController = GovernanceControllerOApp(governanceControllerAddress);

        // The raw bytes message to send
        // Serialized governance message goes here
        bytes memory messageBytes = hex"";

        // Set up options with gas limit
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(4000000, 4000000);

        // Quote the fee
        MessagingFee memory fee = governanceController.quoteRawBytesAction(messageBytes, dstEid, options, false);

        // Send the message
        governanceController.sendRawBytesAction{value: fee.nativeFee}(
            messageBytes,
            dstEid,
            options,
            fee,
            msg.sender // refund address
        );

        vm.stopBroadcast();
    }
}
