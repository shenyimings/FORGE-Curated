// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DeployBase} from "script/deployers/DeployBase.sol";
import {Migrator} from "src/migration/Migrator.sol";
import {Deployer} from "src/utils/Deployer.sol";

contract DeployMigrator is Script {
    function run() public returns (address) {
        Deployer deployer = Deployer(payable(0xc781BaD08968E324D1B91Be3cca30fAd86E7BF98));
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        bytes32 salt = getSalt("MigratorV1.0.0");

        console.log("Deploying Migrator");

        address created = deployer.precompute(salt);

        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created =
                deployer.create(salt, type(Migrator).creationCode);
            vm.stopBroadcast();
            console.log("Migrator deployed at: %s", created);
        } else {
            console.log("Using existing Migrator at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}