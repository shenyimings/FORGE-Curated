// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20} from "../contracts/extensions/ERC20.sol";
import {LaunchList} from "../contracts/LaunchList.sol";

contract DeployToken is Script {
    function run() external {
        // Get the Ledger deployer address
        // Default to the first account (index 0) on the Ledger with Legacy HD path
        uint256 ledgerIndex = vm.envOr("LEDGER_INDEX", uint256(0));
        string memory hdPath = "m/44'/60'/0'/0";
        address deployer = vm.envAddress("LEDGER_ADDRESS");

        if (deployer == address(0)) {
            console2.log("Error: No deployer address provided. Set LEDGER_ADDRESS environment variable.");
            return;
        }

        console2.log("Using Ledger deployer address:", deployer);
        console2.log("Using Ledger account index:", ledgerIndex);
        console2.log("Using Ledger HD path:", hdPath);

        // Start broadcasting transactions using the Ledger with legacy HD path
        vm.startBroadcast(deployer);

        // 1. Deploy LaunchList contract
        LaunchList launchList = new LaunchList(deployer);

        // 2. Deploy Token contract
        ERC20 token = new ERC20("Vultisig Token", "VULT");

        // 3. Configure token with launch list
        token.setLaunchListContract(address(launchList));

        // 4. Set initial phase (optional - you can do this later)
        launchList.setPhase(LaunchList.Phase.LAUNCH_LIST_ONLY);

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Deployed contracts:");
        console2.log("Token:", address(token));
        console2.log("LaunchList:", address(launchList));
    }
}
