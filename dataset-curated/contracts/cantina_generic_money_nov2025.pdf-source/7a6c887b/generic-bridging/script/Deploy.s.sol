// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { Config } from "forge-std/Config.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BridgeCoordinator } from "../src/coordinator/BridgeCoordinator.sol";
import { BridgeCoordinatorL1 } from "../src/BridgeCoordinatorL1.sol";
import { BridgeCoordinatorL2 } from "../src/BridgeCoordinatorL2.sol";
import { LayerZeroAdapter } from "../src/adapters/LayerZeroAdapter.sol";
import { LineaBridgeAdapter } from "../src/adapters/LineaBridgeAdapter.sol";

/// @dev `[{chain alias or id}.address]` must be present in deployments.toml
/// otherwise config.set() reverts with ChainNotInitialized error
contract Deploy is Script, Config {
    /// forge script script/Deploy.s.sol:Deploy -f {chain alias}
    function run() external {
        _loadConfig("./addrs/external.toml", false);

        address unitToken = config.get("generic_unit_token").toAddress();
        require(unitToken != address(0), "unit token not set");
        console.log("Unit token address:", unitToken);

        address admin = config.get("bridging_admin").toAddress();
        require(admin != address(0), "admin not set");
        console.log("Admin address:", admin);

        address coordinatorRolesAdmin = config.get("bridge_coordinator_roles_admin").toAddress();
        require(coordinatorRolesAdmin != address(0), "roles admin not set");
        console.log("Coordinator roles admin address:", coordinatorRolesAdmin);

        address lzEndpoint = config.get("layerzero_endpoint").toAddress();
        // Note: LayerZero adapter deployment is optional
        console.log("LayerZero Endpoint address:", lzEndpoint);

        bool isL1 = config.get("is_l1").toBool();
        console.log("Is L1:", isL1);

        address coordinatorAdapterManager = config.get("bridge_coordinator_adapter_manager").toAddress();
        require(coordinatorAdapterManager != address(0), "adapter manager not set");
        console.log("Coordinator adapter manager address:", coordinatorAdapterManager);

        address coordinatorPredepositManager;
        if (isL1) {
            coordinatorPredepositManager = config.get("bridge_coordinator_predeposit_manager").toAddress();
            require(coordinatorPredepositManager != address(0), "predeposit manager not set");
            console.log("Coordinator predeposit manager address:", coordinatorPredepositManager);
        }

        _loadConfig("./addrs/deployments.toml", true);

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        // Deploy BridgeCoordinator with caller as initial admin
        address coordinatorImpl = isL1 ? address(new BridgeCoordinatorL1()) : address(new BridgeCoordinatorL2());
        address coordinator = address(
            new TransparentUpgradeableProxy(
                coordinatorImpl, admin, abi.encodeCall(BridgeCoordinator.initialize, (unitToken, msg.sender))
            )
        );

        // Deploy LineaBridgeAdapter
        address lineaAdapter = address(new LineaBridgeAdapter(BridgeCoordinator(coordinator), admin));

        // Deploy LayerZeroAdapter
        address layerZeroAdapter;
        if (lzEndpoint != address(0)) {
            layerZeroAdapter = address(new LayerZeroAdapter(BridgeCoordinator(coordinator), admin, lzEndpoint));
        }

        // Grant ADAPTER_MANAGER_ROLE
        BridgeCoordinator(coordinator)
            .grantRole(BridgeCoordinator(coordinator).ADAPTER_MANAGER_ROLE(), coordinatorAdapterManager);
        console.log("BridgeCoordinator ADAPTER_MANAGER_ROLE granted to:", coordinatorAdapterManager);

        // Grant PREDEPOSIT_MANAGER_ROLE
        if (isL1 && coordinatorPredepositManager != address(0)) {
            BridgeCoordinatorL1(coordinator)
                .grantRole(BridgeCoordinatorL1(coordinator).PREDEPOSIT_MANAGER_ROLE(), coordinatorPredepositManager);
            console.log("BridgeCoordinatorL1 PREDEPOSIT_MANAGER_ROLE granted to:", coordinatorPredepositManager);
        }

        // Transfer DEFAULT_ADMIN_ROLE
        if (msg.sender != coordinatorRolesAdmin) {
            BridgeCoordinator(coordinator).grantRole(BridgeCoordinator(coordinator).DEFAULT_ADMIN_ROLE(), msg.sender);
            BridgeCoordinator(coordinator)
                .revokeRole(BridgeCoordinator(coordinator).DEFAULT_ADMIN_ROLE(), coordinatorRolesAdmin);
        }
        console.log("BridgeCoordinator DEFAULT_ADMIN_ROLE granted to:", coordinatorRolesAdmin);

        vm.stopBroadcast();

        // Save addresses to deployments.toml
        config.set(isL1 ? "bridge_coordinator_l1" : "bridge_coordinator_l2", coordinator);
        config.set("linea_adapter", lineaAdapter);
        if (lzEndpoint != address(0)) config.set("layerzero_adapter", layerZeroAdapter);

        // Log deployed addresses
        console.log("----------");
        console.log("New deployments:\n");

        console.log("LineaBridgeAdapter deployed at:", lineaAdapter);
        console.log(isL1 ? "BridgeCoordinatorL1 deployed at" : "BridgeCoordinatorL2 deployed at", coordinator);
        if (lzEndpoint != address(0)) {
            console.log("LayerZeroAdapter deployed at:", layerZeroAdapter);
        } else {
            console.log("LayerZeroAdapter deployment skipped (endpoint address not set)");
        }
    }

    /// forge script script/Deploy.s.sol:Deploy --sig "deployLayerZeroAdapter()" -f {chain alias}
    function deployLayerZeroAdapter() external {
        _loadConfig("./addrs/external.toml", false);

        address admin = config.get("bridging_admin").toAddress();
        require(admin != address(0), "admin not set");
        console.log("Admin address:", admin);

        address lzEndpoint = config.get("layerzero_endpoint").toAddress();
        require(lzEndpoint != address(0), "layerzero endpoint not set");
        console.log("LayerZero Endpoint address:", lzEndpoint);

        bool isL1 = config.get("is_l1").toBool();
        console.log("Is L1:", isL1);

        _loadConfig("./addrs/deployments.toml", true);

        string memory key = isL1 ? "bridge_coordinator_l1" : "bridge_coordinator_l2";
        address coordinator = config.get(key).toAddress();
        require(coordinator != address(0), "bridge coordinator not set");
        string memory desc = isL1 ? "BridgeCoordinatorL1 address" : "BridgeCoordinatorL2 address";
        console.log(desc, coordinator);

        vm.createSelectFork(config.getRpcUrl());
        vm.startBroadcast();

        // Deploy LayerZeroAdapter
        address adapter = address(new LayerZeroAdapter(BridgeCoordinator(coordinator), admin, lzEndpoint));

        vm.stopBroadcast();

        // Save address to deployments.toml
        config.set("layerzero_adapter", adapter);

        // Log deployed address
        console.log("----------");
        console.log("New deployments:\n");

        console.log("LayerZeroAdapter deployed at:", adapter);
    }
}
