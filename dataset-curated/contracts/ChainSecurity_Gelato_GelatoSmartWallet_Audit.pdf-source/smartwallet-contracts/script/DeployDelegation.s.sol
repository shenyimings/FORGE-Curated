// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Delegation} from "../src/Delegation.sol";
import {BaseScript} from "./Base.s.sol";

contract DeployDelegation is BaseScript {
    function run() public broadcast returns (Delegation delegation) {
        /// Check if default deterministic deployer is deployed
        /// https://github.com/Arachnid/deterministic-deployment-proxy
        address deterministicDeployer = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
        if (deterministicDeployer.code.length == 0) {
            revert("Deterministic deployer not deployed");
        }

        delegation = new Delegation{salt: GELATO_SALT}();
    }
}
