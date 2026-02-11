// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console } from "../../lib/forge-std/src/console.sol";
import { Script } from "../../lib/forge-std/src/Script.sol";

import { DeployMUSDBase } from "./DeployMUSDBase.sol";

contract DeployMUSD is DeployMUSDBase, Script {
    function run() external {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        address yieldRecipient = vm.envAddress("YIELD_RECIPIENT");
        address admin = vm.envAddress("ADMIN");
        address freezeManager = vm.envAddress("FREEZE_MANAGER");
        address yieldRecipientManager = vm.envAddress("YIELD_RECIPIENT_MANAGER");
        address pauser = vm.envAddress("PAUSER");
        address forcedTransferManager = vm.envAddress("FORCED_TRANSFER_MANAGER");

        vm.startBroadcast(deployer);

        (address implementation, address proxy, address proxyAdmin) = _deployMUSD(
            deployer,
            M_TOKEN,
            SWAP_FACILITY,
            yieldRecipient,
            admin,
            freezeManager,
            yieldRecipientManager,
            pauser,
            forcedTransferManager
        );

        vm.stopBroadcast();

        console.log("MUSD successfully deployed on chain ID %s: ", block.chainid);
        console.log("Implementation: %s", implementation);
        console.log("Proxy: %s", proxy);
        console.log("ProxyAdmin: %s", proxyAdmin);
    }
}
