// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Swap} from "../src/Swap.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {AssetIssuer} from "../src/AssetIssuer.sol";
import {AssetRebalancer} from "../src/AssetRebalancer.sol";
import {AssetFeeManager} from "../src/AssetFeeManager.sol";
import {StakeFactory} from "../src/StakeFactory.sol";
import {StakeToken} from "../src/StakeToken.sol";
import {AssetLocking} from "../src/AssetLocking.sol";
import {USSI} from "../src/USSI.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

contract UpgradeScript is Script {
    function setUp() public {}

    function run() public {
        string memory referenceBuildInfoDir = vm.envString("REFER_BUILD_DIR");
        vm.startBroadcast();
        // impl
        Options memory options;
        options.referenceBuildInfoDir = referenceBuildInfoDir;
        options.referenceContract = "build-info-v1:AssetToken";
        address tokenImpl = Upgrades.deployImplementation("AssetToken.sol:AssetToken", options);
        options.referenceContract = "build-info-v1:AssetFactory";
        address factoryImpl = Upgrades.deployImplementation("AssetFactory.sol:AssetFactory", options);
        options.referenceContract = "build-info-v1:StakeToken";
        address stakeTokenImpl = Upgrades.deployImplementation("StakeToken.sol:StakeToken", options);
        options.referenceContract = "build-info-v1:StakeFactory";
        address stakeFactoryImpl = Upgrades.deployImplementation("StakeFactory.sol:StakeFactory", options);
        options.referenceContract = "build-info-v1:AssetLocking";
        address assetLockingImpl = Upgrades.deployImplementation("AssetLocking.sol:AssetLocking", options);
        options.referenceContract = "build-info-v1:USSI";
        address uSSIImpl = Upgrades.deployImplementation("USSI.sol:USSI", options);
        options.referenceContract = "build-info-v1:AssetIssuer";
        address issuerImpl = Upgrades.deployImplementation("AssetIssuer.sol:AssetIssuer", options);
        options.referenceContract = "build-info-v1:AssetRebalancer";
        address rebalancerImpl = Upgrades.deployImplementation("AssetRebalancer.sol:AssetRebalancer", options);
        options.referenceContract = "build-info-v1:AssetFeeManager";
        address feeManagerImpl = Upgrades.deployImplementation("AssetFeeManager.sol:AssetFeeManager", options);
        options.referenceContract = "build-info-v1:Swap";
        address swapImpl = Upgrades.deployImplementation("Swap.sol:Swap", options);
        vm.stopBroadcast();
        // impl
        console.log(string.concat("issuerImpl=", vm.toString(address(issuerImpl))));
        console.log(string.concat("rebalancerImpl=", vm.toString(address(rebalancerImpl))));
        console.log(string.concat("feeManagerImpl=", vm.toString(address(feeManagerImpl))));
        console.log(string.concat("tokenImpl=", vm.toString(address(tokenImpl))));
        console.log(string.concat("factoryImpl=", vm.toString(address(factoryImpl))));
        console.log(string.concat("stakeTokenImpl=", vm.toString(address(stakeTokenImpl))));
        console.log(string.concat("stakeFactoryImpl=", vm.toString(address(stakeFactoryImpl))));
        console.log(string.concat("assetLockingImpl=", vm.toString(address(assetLockingImpl))));
        console.log(string.concat("uSSIImpl=", vm.toString(address(uSSIImpl))));
        console.log(string.concat("swapImpl=", vm.toString(address(swapImpl))));
    }
}
