// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { stdJson } from "forge-std/StdJson.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

enum SlasherType {
    INSTANT,
    VETO
}

enum DelegatorType {
    NETWORK_RESTAKE,
    FULL_RESTAKE,
    OPERATOR_SPECIFIC,
    OPERATOR_NETWORK_SPECIFIC
}

struct SymbioticFactories {
    address vaultFactory;
    address delegatorFactory;
    address slasherFactory;
    address defaultStakerRewardsFactory;
    address defaultOperatorRewardsFactory;
    address burnerRouterFactory;
}

struct SymbioticRegistries {
    address networkRegistry;
    address vaultRegistry;
    address operatorRegistry;
}

struct SymbioticServices {
    address networkMetadataService;
    address networkMiddlewareService;
    address operatorMetadataService;
    address vaultOptInService;
    address networkOptInService;
    address vaultConfigurator;
}

struct SymbioticAddressbook {
    SymbioticFactories factories;
    SymbioticRegistries registries;
    SymbioticServices services;
}

struct VaultAddressbook {
    address vault;
    address curator;
    address delegator;
    address slasher;
}

contract SymbioticUtils {
    using stdJson for string;

    string public constant SYMBIOTIC_CONFIG_PATH_FROM_PROJECT_ROOT = "config/symbiotic.json";

    function _getSymbioticAddressbook() internal view returns (SymbioticAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = vm.readFile(SYMBIOTIC_CONFIG_PATH_FROM_PROJECT_ROOT);
        string memory selectorPrefix = string.concat("$['", vm.toString(block.chainid), "']");

        console.log("block.chainid", block.chainid);

        // ethereum sepolia
        ab.factories.vaultFactory = configJson.readAddress(string.concat(selectorPrefix, ".factories.vaultFactory"));
        ab.factories.delegatorFactory =
            configJson.readAddress(string.concat(selectorPrefix, ".factories.delegatorFactory"));
        ab.factories.slasherFactory = configJson.readAddress(string.concat(selectorPrefix, ".factories.slasherFactory"));
        ab.factories.defaultStakerRewardsFactory =
            configJson.readAddress(string.concat(selectorPrefix, ".factories.defaultStakerRewardsFactory"));
        ab.factories.defaultOperatorRewardsFactory =
            configJson.readAddress(string.concat(selectorPrefix, ".factories.defaultOperatorRewardsFactory"));
        ab.factories.burnerRouterFactory =
            configJson.readAddress(string.concat(selectorPrefix, ".factories.burnerRouterFactory"));

        ab.registries.networkRegistry =
            configJson.readAddress(string.concat(selectorPrefix, ".registries.networkRegistry"));
        ab.registries.vaultRegistry = configJson.readAddress(string.concat(selectorPrefix, ".registries.vaultRegistry"));
        ab.registries.operatorRegistry =
            configJson.readAddress(string.concat(selectorPrefix, ".registries.operatorRegistry"));

        ab.services.networkMetadataService =
            configJson.readAddress(string.concat(selectorPrefix, ".services.networkMetadataService"));
        ab.services.networkMiddlewareService =
            configJson.readAddress(string.concat(selectorPrefix, ".services.networkMiddlewareService"));
        ab.services.operatorMetadataService =
            configJson.readAddress(string.concat(selectorPrefix, ".services.operatorMetadataService"));
        ab.services.vaultOptInService =
            configJson.readAddress(string.concat(selectorPrefix, ".services.vaultOptInService"));
        ab.services.networkOptInService =
            configJson.readAddress(string.concat(selectorPrefix, ".services.networkOptInService"));
        ab.services.vaultConfigurator =
            configJson.readAddress(string.concat(selectorPrefix, ".services.vaultConfigurator"));
    }

    function _getSymbioticVaultAddressbook(address asset) internal view returns (VaultAddressbook memory ab) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        string memory configJson = vm.readFile(SYMBIOTIC_CONFIG_PATH_FROM_PROJECT_ROOT);
        string memory selectorPrefix =
            string.concat("$['", vm.toString(block.chainid), "'].vaults[", vm.toString(asset), "]");

        ab.vault = configJson.readAddress(string.concat(selectorPrefix, ".vault"));
        ab.curator = configJson.readAddress(string.concat(selectorPrefix, ".curator"));
        ab.delegator = configJson.readAddress(string.concat(selectorPrefix, ".delegator"));
        ab.slasher = configJson.readAddress(string.concat(selectorPrefix, ".slasher"));
    }
}
