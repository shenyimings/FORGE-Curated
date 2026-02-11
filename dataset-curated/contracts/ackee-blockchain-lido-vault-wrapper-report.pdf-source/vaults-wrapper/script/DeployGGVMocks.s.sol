// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {GGVVaultMock} from "src/mock/ggv/GGVVaultMock.sol";

contract DeployGGVMocks is Script {
    function run() external {
        string memory outputJsonPath = _getOutputPath();

        address steth = vm.envOr("STETH", address(0));
        address wsteth = vm.envOr("WSTETH", address(0));
        address owner = vm.envOr("GGV_OWNER", address(0));
        require(steth != address(0) && wsteth != address(0), "STETH and WSTETH must be set");
        // Owner is optional; if unset, default to the deployer EOA used for broadcasting
        if (owner == address(0)) owner = tx.origin;

        vm.startBroadcast();
        GGVVaultMock vault = new GGVVaultMock(owner, steth, wsteth);
        vm.stopBroadcast();

        address teller = address(vault.TELLER());
        address queue = address(vault.BORING_QUEUE());

        string memory out = vm.serializeAddress("ggv", "boringVault", address(vault));
        out = vm.serializeAddress("ggv", "teller", teller);
        out = vm.serializeAddress("ggv", "boringOnChainQueue", queue);
        vm.writeJson(out, outputJsonPath);

        console2.log("GGV mocks deployed:");
        console2.log("  vault:", address(vault));
        console2.log("  teller:", address(teller));
        console2.log("  queue:", address(queue));
        console2.log("Output written to", outputJsonPath);
    }

    function _getOutputPath() internal view returns (string memory p) {
        // Prefer env var if provided, fallback to deployments/ggv-mocks-<network>.json
        try vm.envString("GGV_MOCKS_DEPLOYED_JSON") returns (string memory provided) {
            if (bytes(provided).length != 0) {
                return provided;
            }
        } catch {}
        string memory network = "local";
        try vm.envString("NETWORK") returns (string memory n) {
            if (bytes(n).length != 0) network = n;
        } catch {}
        return string(abi.encodePacked("deployments/ggv-mocks-", network, ".json"));
    }
}
