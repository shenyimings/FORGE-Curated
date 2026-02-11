// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Counter} from "src/Counter.sol";
import {Script, console} from "forge-std/Script.sol";

// forge script script/deployers/DeployCounter.s.sol:DeployCounter --slow --rpc-url <> --broadcast
contract DeployCounter is Script {
    function run() public {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(key);

        address created = address(new Counter());
        console.log(" Counter deployed at: %s", created);

        vm.stopBroadcast();
    }
}
