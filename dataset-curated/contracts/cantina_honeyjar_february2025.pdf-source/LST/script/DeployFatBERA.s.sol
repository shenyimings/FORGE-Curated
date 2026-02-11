// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/fatBERA.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployFatBERA is Script {
    // Configuration
    uint256 constant maxDeposits = 9_300_000 ether;
    address constant WBERA = 0x6969696969696969696969696969696969696969;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        bytes memory initData = abi.encodeWithSelector(fatBERA.initialize.selector, WBERA, deployer, maxDeposits);

        address proxy = Upgrades.deployUUPSProxy("fatBERA.sol:fatBERA", initData);

        fatBERA(proxy).setRewardsDuration(WBERA, 2 days);

        // // Approve and deposit 1 WBERA
        // IERC20(WBERA).approve(proxy, 1 ether);
        // fatBERA(proxy).deposit(1 ether, deployer);

        vm.stopBroadcast();

        console.log("fatBERA proxy deployed to: %s", proxy);
        console.log("Implementation deployed at: %s", Upgrades.getImplementationAddress(proxy));
        console.log("Contract owner set to: %s", deployer);
        console.log("Max deposits set to: %d", maxDeposits);
        console.log("Contract paused by default");
        console.log("Initial deposit of 1 WBERA made by admin");
    }
}
