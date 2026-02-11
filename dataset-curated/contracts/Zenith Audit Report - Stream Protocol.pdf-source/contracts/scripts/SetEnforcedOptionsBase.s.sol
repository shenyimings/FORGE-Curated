// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StableWrapper} from "../src/StableWrapper.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";


contract SetEnforcedOptionsBaseScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Chain IDs
        uint32 ARB_SEPOLIA_EID = 40231;

        // Create array of enforced options
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
        params[0].eid = ARB_SEPOLIA_EID;
        params[0].msgType = 1;  // SEND
        params[0].options = hex"0003010011010000000000000000000000000000ea60";  // 60k gas

        vm.startBroadcast(deployerPrivateKey);

        // Call directly with the same struct type
        StableWrapper(0x450607C6A43F9Acb671aff183dD2Bd048261DD70).setEnforcedOptions(params);  // BASE_WRAPPER
        StreamVault(0x2B890881268172d1697eB7bc9744F8424E5A3f5a).setEnforcedOptions(params);    // BASE_VAULT

        vm.stopBroadcast();
    }
}