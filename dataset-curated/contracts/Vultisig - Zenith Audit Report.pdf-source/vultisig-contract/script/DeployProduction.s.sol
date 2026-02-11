// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Stake} from "../contracts/Stake.sol";
import {StakeSweeper} from "../contracts/StakeSweeper.sol";
import {console2} from "forge-std/console2.sol";

contract DeployProductionScript is Script {
    function run() external {
        // Load configuration from environment variables
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");

        // Validate addresses
        require(stakingToken != address(0), "Invalid staking token address");
        require(rewardToken != address(0), "Invalid reward token address");
        require(uniswapRouter != address(0), "Invalid router address");

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

        // Deploy StakeSweeper
        StakeSweeper sweeper = new StakeSweeper(rewardToken, uniswapRouter);

        // Deploy Stake contract
        Stake stakeContract = new Stake(stakingToken, rewardToken);

        // Configure Stake contract
        stakeContract.setSweeper(address(sweeper));
        stakeContract.setRewardDecayFactor(10); // 10% of rewards released per update
        stakeContract.setMinRewardUpdateDelay(1 days);

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("Production Deployment Summary:");
        console2.log("-----------------------------");
        console2.log("StakeSweeper:", address(sweeper));
        console2.log("Stake Contract:", address(stakeContract));
    }
}
