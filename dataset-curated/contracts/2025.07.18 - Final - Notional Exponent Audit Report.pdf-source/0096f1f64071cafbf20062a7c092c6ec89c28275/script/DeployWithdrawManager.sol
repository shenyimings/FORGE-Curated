// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {AddressRegistry} from "../src/proxy/AddressRegistry.sol";

abstract contract DeployWithdrawManager is Script, GnosisHelper {

    function deployWithdrawManager() internal virtual returns (address impl);

    function run() public {
        vm.startBroadcast();
        address impl = deployWithdrawManager();
        console.log("WithdrawManager deployed at", impl);
        vm.stopBroadcast();

        MethodCall[] memory calls = new MethodCall[](1);
        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(AddressRegistry.setWithdrawRequestManager.selector, impl, false)
        });

        generateBatch("list-withdraw-manager.json", calls);
    }
}