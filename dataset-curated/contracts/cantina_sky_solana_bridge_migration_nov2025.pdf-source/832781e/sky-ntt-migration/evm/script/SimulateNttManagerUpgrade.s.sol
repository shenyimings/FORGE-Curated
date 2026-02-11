// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {console2} from "forge-std/Script.sol";

import "../src/interfaces/INttManager.sol";
import "../src/interfaces/IManagerBase.sol";

import {NttManager} from "../src/NttManager/NttManager.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "../src/libraries/PausableUpgradeable.sol";

import {ParseNttConfig} from "./helpers/ParseNttConfig.sol";

contract SimulateNttManagerUpgradeScript is ParseNttConfig {
    struct DeploymentParams {
        address token;
        INttManager.Mode mode;
        uint16 wormholeChainId;
        uint64 rateLimitDuration;
        bool shouldSkipRatelimiter;
    }

    function upgradeNttManager(
        INttManager nttManagerProxy,
        DeploymentParams memory params
    ) internal {
        // Deploy the Manager Implementation.
        NttManager implementation = new NttManager(
            params.token,
            params.mode,
            params.wormholeChainId,
            params.rateLimitDuration,
            params.shouldSkipRatelimiter
        );

        console2.log("NttManager Implementation deployed at: ", address(implementation));

        // Upgrade the proxy.
        nttManagerProxy.upgrade(address(implementation));
    }

    function run() public {
        DeploymentParams memory params = DeploymentParams({
            token: 0xdC035D45d973E3EC169d2276DDab16f1e407384F,
            mode: IManagerBase.Mode.LOCKING,
            wormholeChainId: 2,
            rateLimitDuration: 86400,
            shouldSkipRatelimiter: false
        });
        NttManager nttManager = NttManager(0x7d4958454a3f520bDA8be764d06591B054B0bf33);

        console2.log("before upgrade");
        console2.log("Is NttManager paused: ", nttManager.isPaused());

        vm.startPrank(nttManager.owner());
        upgradeNttManager(nttManager, params);
        vm.stopPrank();

        console2.log("after upgrade");
        console2.log("Is NttManager paused: ", nttManager.isPaused());

        vm.prank(nttManager.owner());
        nttManager.pause();

        console2.log("after pauseSend");
        console2.log("Is NttManager paused: ", nttManager.isPaused());
    }
}
