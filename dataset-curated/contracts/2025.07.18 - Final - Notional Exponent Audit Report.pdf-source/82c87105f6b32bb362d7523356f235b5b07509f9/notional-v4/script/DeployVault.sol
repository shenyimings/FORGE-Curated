// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import {TimelockUpgradeableProxy} from "../src/proxy/TimelockUpgradeableProxy.sol";
import {Initializable} from "../src/proxy/Initializable.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";

abstract contract DeployVault is Script, GnosisHelper {

    function deployVault() internal virtual returns (address impl);
    function postDeploySetup() internal virtual returns (MethodCall[] memory calls);

    function name() internal virtual returns (string memory);
    function symbol() internal virtual returns (string memory);

    function run() public {
        vm.startBroadcast();
        address impl = deployVault();
        console.log("Vault implementation deployed at", impl);
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(impl),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(name(), symbol()))
        );
        console.log("Vault proxy deployed at", address(proxy));
        vm.stopBroadcast();

        generateBatch("deploy-vault.json", postDeploySetup());
    }
}