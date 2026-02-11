// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ICheckpointHook} from "../src/Firewall.sol";
import "../src/ExternalFirewall.sol";
import "../src/SecurityValidator.sol";

contract DummyFirewallAccess {
    function isFirewallAdmin(address) public pure returns (bool) {
        return true;
    }

    function isProtocolAdmin(address) public pure returns (bool) {
        return true;
    }

    function isCheckpointManager(address) public pure returns (bool) {
        return true;
    }

    function isLogicUpgrader(address) public pure returns (bool) {
        return true;
    }

    function isCheckpointExecutor(address) public pure returns (bool) {
        return true;
    }

    function isTrustedAttester(address) public pure returns (bool) {
        return true;
    }
}

contract FirewallDeployerScript is Script {
    function run() public {
        string memory deployerPrivateKeyStr = vm.envString("DEPLOY_KEY");
        uint256 deployer = vm.parseUint(deployerPrivateKeyStr);
        vm.startBroadcast(deployer);

        SecurityValidator validator = new SecurityValidator(address(0));
        ExternalFirewall externalFirewall = new ExternalFirewall(
            ISecurityValidator(address(validator)),
            ICheckpointHook(address(0)),
            bytes32(0),
            IFirewallAccess(address(new DummyFirewallAccess()))
        );
        console.log("validator contract:", address(validator));
        console.log("external firewall contract:", address(externalFirewall));

        vm.stopBroadcast();
    }
}
