// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "../contracts/DIAExternalStaking.sol";
import "../contracts/DIAWhitelistedStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployStaking is Script {
    function run() external {
        // Get deployment parameters from environment variables
        uint256 unstakingDuration = vm.envUint("UNSTAKING_DURATION");
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        uint256 stakingLimit = vm.envUint("STAKING_LIMIT");
        address rewardsWallet = vm.envAddress("REWARDS_WALLET");
        uint256 rewardRatePerDay = vm.envUint("REWARD_RATE_PER_DAY");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy DIAExternalStaking
        DIAExternalStaking externalStaking = new DIAExternalStaking(
            unstakingDuration,
            stakingToken,
            stakingLimit
        );

        // Deploy DIAWhitelistedStaking
        DIAWhitelistedStaking whitelistedStaking = new DIAWhitelistedStaking(
            unstakingDuration,
            stakingToken,
            rewardsWallet,
            rewardRatePerDay
        );

        // Configure contracts
        externalStaking.setWithdrawalCapBps(10000); // 100%
        whitelistedStaking.setWithdrawalCapBps(10000); // 100%

        // Set daily withdrawal thresholds
        externalStaking.setDailyWithdrawalThreshold(100000 * 10 ** 18);
        whitelistedStaking.setDailyWithdrawalThreshold(100000 * 10 ** 18);

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("DIAExternalStaking deployed to:", address(externalStaking));
        console.log("DIAWhitelistedStaking deployed to:", address(whitelistedStaking));

        // Verify contracts
        string memory verifyCommand = string.concat(
            "forge verify-contract ",
            "--verifier blockscout ",
            "--verifier-url https://testnet-explorer.diadata.org/api ",
            vm.toString(address(externalStaking)),
            " DIAExternalStaking ",
            vm.toString(unstakingDuration),
            " ",
            vm.toString(stakingToken),
            " ",
            vm.toString(stakingLimit)
        );
        console.log("Run this command to verify DIAExternalStaking:");
        console.log(verifyCommand);

        verifyCommand = string.concat(
            "forge verify-contract ",
            "--verifier blockscout ",
            "--verifier-url https://testnet-explorer.diadata.org/api ",
            vm.toString(address(whitelistedStaking)),
            " DIAWhitelistedStaking ",
            vm.toString(unstakingDuration),
            " ",
            vm.toString(stakingToken),
            " ",
            vm.toString(rewardsWallet),
            " ",
            vm.toString(rewardRatePerDay)
        );
        console.log("Run this command to verify DIAWhitelistedStaking:");
        console.log(verifyCommand);
    }
} 