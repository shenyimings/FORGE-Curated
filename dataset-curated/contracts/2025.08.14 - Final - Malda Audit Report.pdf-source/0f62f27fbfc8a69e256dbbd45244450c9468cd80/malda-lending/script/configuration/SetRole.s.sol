// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Roles} from "src/Roles.sol";
import {Script, console} from "forge-std/Script.sol";

contract SetRole is Script {
    function run(address rolesContract, address receiver, bytes32 role, bool status) public virtual {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        console.log("Setting role for %s", receiver);

        if (Roles(rolesContract).isAllowedFor(receiver, role) == status) {
            console.log("Role already set");
            return;
        }

        vm.startBroadcast(key);
        Roles(rolesContract).allowFor(receiver, role, status);
        vm.stopBroadcast();

        if (status) {
            console.log("Added role for %s", receiver);
        } else {
            console.log(" Removed role for %s", receiver);
        }
    }
}
