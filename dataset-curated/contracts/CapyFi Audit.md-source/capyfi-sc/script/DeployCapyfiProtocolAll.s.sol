// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployCapyfiProtocolAll is Script {
    function run() external returns (HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        helperConfig.setConfig(block.chainid, config);
        return (helperConfig);
    }
}
