// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {Swap} from "../src/Swap.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {AssetIssuer} from "../src/AssetIssuer.sol";
import {AssetRebalancer} from "../src/AssetRebalancer.sol";
import {AssetFeeManager} from "../src/AssetFeeManager.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

contract UpgradeAssetController is Script {
    function setUp() public {}

    function run() public {
        address owner = vm.envAddress("OWNER");
        address swapProxy = vm.envAddress("SWAP_PROXY");
        address assetFactoryProxy = vm.envAddress("ASSET_FACTORY_PROXY");
        address assetIssuerProxy = vm.envAddress("ASSET_ISSUER_PROXY");
        address assetRebalancerProxy = vm.envAddress("ASSET_REBALANCER_PROXY");
        address assetFeeManagerProxy = vm.envAddress("ASSET_FEEMANAGER_PROXY");

        vm.startBroadcast();

        // Upgrade Swap
        Options memory swapOptions;
        swapOptions.unsafeSkipStorageCheck = true;
        Upgrades.upgradeProxy(swapProxy, "Swap.sol", "", swapOptions);
        address newSwapImpl = Upgrades.getImplementationAddress(swapProxy);
        console.log(
            string.concat(
                "Upgraded Swap proxy to new implementation at: ",
                vm.toString(newSwapImpl)
            )
        );

        // Upgrade AssetFactory
        Options memory factoryOptions;
        factoryOptions.unsafeSkipStorageCheck = true;
        Upgrades.upgradeProxy(
            assetFactoryProxy,
            "AssetFactory.sol",
            "",
            factoryOptions
        );
        address newAssetFactoryImpl = Upgrades.getImplementationAddress(
            assetFactoryProxy
        );
        console.log(
            string.concat(
                "Upgraded AssetFactory proxy to new implementation at: ",
                vm.toString(newAssetFactoryImpl)
            )
        );

        // Upgrade AssetIssuer
        Options memory issueOptions;
        issueOptions.unsafeSkipStorageCheck = true;
        Upgrades.upgradeProxy(
            assetIssuerProxy,
            "AssetIssuer.sol",
            "",
            issueOptions
        );
        address newAssetIssuerImpl = Upgrades.getImplementationAddress(
            assetIssuerProxy
        );
        console.log(
            string.concat(
                "Upgraded AssetIssuer proxy to new implementation at: ",
                vm.toString(newAssetIssuerImpl)
            )
        );

        // Upgrade AssetRebalancer
        Options memory rebalancerOptions;
        rebalancerOptions.unsafeSkipStorageCheck = true;
        Upgrades.upgradeProxy(
            assetRebalancerProxy,
            "AssetRebalancer.sol",
            "",
            rebalancerOptions
        );
        address newAssetRebalancerImpl = Upgrades.getImplementationAddress(
            assetRebalancerProxy
        );
        console.log(
            string.concat(
                "Upgraded AssetRebalancer proxy to new implementation at: ",
                vm.toString(newAssetRebalancerImpl)
            )
        );

        // Upgrade AssetFeeManager
        Options memory feemanagerOptions;
        feemanagerOptions.unsafeSkipStorageCheck = true;
        Upgrades.upgradeProxy(
            assetFeeManagerProxy,
            "AssetFeeManager.sol",
            "",
            feemanagerOptions
        );
        address newAssetFeeManagerImpl = Upgrades.getImplementationAddress(
            assetFeeManagerProxy
        );
        console.log(
            string.concat(
                "Upgraded AssetFeeManager proxy to new implementation at: ",
                vm.toString(newAssetFeeManagerImpl)
            )
        );

        vm.stopBroadcast();
    }
}
