// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";

contract DeployTimelockController is Script {
    function run(Deployer _deployer, address owner) public returns (address) {
        bytes32 salt = getSalt("TimelockController1.0.0");

        console.log("Deploying TimelockController");

        address created = _deployer.precompute(salt);
        if (created.code.length == 0) {
            vm.startBroadcast(vm.envUint("OWNER_PRIVATE_KEY"));
            //constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin) {
            uint256 minDelay = 3600;
            address[] memory data = new address[](1);
            data[0] = owner;
            created = _deployer.create(salt, abi.encodePacked(type(TimelockController).creationCode, abi.encode(minDelay, data, data, owner)));
            vm.stopBroadcast();
            console.log("TimelockController deployed at: %s", created);
        } else {
            console.log("Using existing TimelockController at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
