// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Flywheel} from "../../src/Flywheel.sol";
import {BridgeReferralFees} from "../../src/hooks/BridgeReferralFees.sol";

/// @notice Script for deploying the BridgeReferralFees hook contract
contract DeployBridgeReferralFees is Script {
    function run(address flywheel, address builderCodes) public returns (address) {
        require(flywheel != address(0), "Flywheel cannot be zero address");
        require(builderCodes != address(0), "Flywheel cannot be zero address");

        uint8 maxFeeBasisPoints = 100;
        address metadataManager = 0x7f2ADee16aaff5870E150b298F5c837CCe65771d; // production smart contract manager key
        string memory uriPrefix = "";

        vm.startBroadcast();

        // Deploy BridgeReferralFees
        BridgeReferralFees hooks = new BridgeReferralFees{salt: 0}(
            flywheel, builderCodes, maxFeeBasisPoints, metadataManager, uriPrefix
        );
        console.log("BridgeReferralFees deployed at:", address(hooks));

        // Create campaign singleton
        address campaign = Flywheel(flywheel).createCampaign(address(hooks), 0, "");
        console.log("Campaign singleton deployed at:", campaign);

        // Activate campaign
        Flywheel(flywheel).updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
        console.log("Campaign activated");

        vm.stopBroadcast();

        return address(hooks);
    }
}
