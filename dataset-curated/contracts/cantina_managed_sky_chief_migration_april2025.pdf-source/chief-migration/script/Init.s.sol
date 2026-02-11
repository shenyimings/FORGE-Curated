// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";

import { stdJson } from "forge-std/StdJson.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { MockSpell } from "test/mocks/MockSpell.sol";

interface PauseProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

contract InitScript is Script {

    using stdJson for string;
    using ScriptTools for string;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    function run() external {
        string memory dependencies = ScriptTools.loadDependencies(); // loads from FOUNDRY_SCRIPT_DEPS
        // string memory config = ScriptTools.loadConfig();          // loads from FOUNDRY_SCRIPT_CONFIG

        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        vm.startBroadcast();

        PauseProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY")).exec(
            dependencies.readAddress(".spell"),
            abi.encodeCall(MockSpell.execute, ())
        );
        vm.stopBroadcast();
    }
}
