// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StableWrapper} from "../src/StableWrapper.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract SetEnforcedOptionsArbitrumScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Chain IDs
        uint32 BASE_SEPOLIA_EID = 40245;

        // Create array of enforced options
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
        params[0].eid = BASE_SEPOLIA_EID;
        params[0].msgType = 1;
        params[0].options = hex"0003010011010000000000000000000000000000ea60";

        vm.startBroadcast(deployerPrivateKey);

        // Call directly with the same struct type
        StableWrapper(0xc380Fc06B25242DbeD574132a0C0e7ED77e8eD28).setEnforcedOptions(params);
        StreamVault(0x58107a168E54802A7D35ebDBE6e9f82447d5Fb8d).setEnforcedOptions(params);

        vm.stopBroadcast();
    }
}
