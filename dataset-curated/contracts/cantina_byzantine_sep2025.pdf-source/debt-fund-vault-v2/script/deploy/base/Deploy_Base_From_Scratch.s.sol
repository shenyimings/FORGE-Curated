// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VaultV2Factory} from "../../../src/VaultV2Factory.sol";
import {MorphoMarketV1AdapterFactory} from "../../../src/adapters/MorphoMarketV1AdapterFactory.sol";
import {MorphoVaultV1AdapterFactory} from "../../../src/adapters/MorphoVaultV1AdapterFactory.sol";
import {CompoundV3AdapterFactory} from "../../../src/adapters/CompoundV3AdapterFactory.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";

/**
 * @notice Script used for the first deployment on Base
 * forge script script/deploy/base/Deploy_Base_From_Scratch.s.sol --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY
 * --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vv
 *
 */
contract Deploy_Base_From_Scratch is Script, Test {
    // Factories
    VaultV2Factory public vaultV2Factory;
    MorphoMarketV1AdapterFactory public morphoMarketV1AdapterFactory;
    MorphoVaultV1AdapterFactory public morphoVaultV1AdapterFactory;
    CompoundV3AdapterFactory public compoundV3AdapterFactory;

    function run() external {
        // START RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.startBroadcast();

        emit log_named_address("Deployer Address", msg.sender);

        _deployFromScratch();

        // STOP RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.stopBroadcast();

        _logAndOutputContractAddresses("./script/deploy/base/Addresses_Base.json");
    }

    function _deployFromScratch() internal {
        // Deploy Factories
        vaultV2Factory = new VaultV2Factory();
        morphoMarketV1AdapterFactory = new MorphoMarketV1AdapterFactory();
        morphoVaultV1AdapterFactory = new MorphoVaultV1AdapterFactory();
        compoundV3AdapterFactory = new CompoundV3AdapterFactory();
    }

    function _logAndOutputContractAddresses(string memory outputPath) internal {
        // WRITE JSON DATA
        string memory parent_object = "parent object";
        string memory deployed_addresses = "addresses";
        string memory chain_info = "chainInfo";

        vm.serializeAddress(deployed_addresses, "vaultV2Factory", address(vaultV2Factory));
        vm.serializeAddress(deployed_addresses, "compoundV3AdapterFactory", address(compoundV3AdapterFactory));
        vm.serializeAddress(deployed_addresses, "morphoMarketV1AdapterFactory", address(morphoMarketV1AdapterFactory));
        string memory deployed_addresses_output =
            vm.serializeAddress(deployed_addresses, "morphoVaultV1AdapterFactory", address(morphoVaultV1AdapterFactory));

        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", block.chainid);

        // serialize all the data
        vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        string memory finalJson = vm.serializeString(parent_object, chain_info, chain_info_output);

        vm.writeJson(finalJson, outputPath);
    }
}
