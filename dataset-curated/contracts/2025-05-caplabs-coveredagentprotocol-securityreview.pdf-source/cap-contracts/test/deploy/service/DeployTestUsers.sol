// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UsersConfig } from "../../../contracts/deploy/interfaces/DeployConfigs.sol";
import { TestUsersConfig } from "../interfaces/TestDeployConfig.sol";
import { Test } from "forge-std/Test.sol";

contract DeployTestUsers is Test {
    function _deployTestUsers() internal returns (UsersConfig memory users, TestUsersConfig memory testUsers) {
        testUsers.agents = new address[](3);
        testUsers.agents[0] = makeAddr("agent_1");
        testUsers.agents[1] = makeAddr("agent_2");
        testUsers.agents[2] = makeAddr("agent_3");

        testUsers.restakers = new address[](3);
        testUsers.restakers[0] = makeAddr("restaker_1");
        testUsers.restakers[1] = makeAddr("restaker_2");
        testUsers.restakers[2] = makeAddr("restaker_3");

        testUsers.stablecoin_minter = makeAddr("stablecoin_minter");
        testUsers.liquidator = makeAddr("liquidator");
        vm.deal(testUsers.agents[0], 100 ether);
        vm.deal(testUsers.agents[1], 100 ether);
        vm.deal(testUsers.agents[2], 100 ether);
        vm.deal(testUsers.stablecoin_minter, 100 ether);
        vm.deal(testUsers.liquidator, 100 ether);

        users.deployer = makeAddr("deployer");
        users.access_control_admin = makeAddr("access_control_admin");
        users.address_provider_admin = makeAddr("address_provider_admin");
        users.oracle_admin = makeAddr("user_oracle_admin");
        users.rate_oracle_admin = makeAddr("user_rate_oracle_admin");
        users.vault_config_admin = makeAddr("user_vault_config_admin");
        users.lender_admin = makeAddr("user_lender_admin");
        users.fee_auction_admin = makeAddr("user_fee_auction_admin");
        users.delegation_admin = makeAddr("user_delegation_admin");
        users.middleware_admin = makeAddr("user_middleware_admin");
        users.staker_rewards_admin = makeAddr("user_staker_rewards_admin");
        users.insurance_fund = makeAddr("insurance_fund");
        vm.deal(users.deployer, 100 ether);
        vm.deal(users.access_control_admin, 100 ether);
        vm.deal(users.address_provider_admin, 100 ether);
        vm.deal(users.oracle_admin, 100 ether);
        vm.deal(users.rate_oracle_admin, 100 ether);
        vm.deal(users.lender_admin, 100 ether);
        vm.deal(users.fee_auction_admin, 100 ether);
        vm.deal(users.vault_config_admin, 100 ether);
        vm.deal(users.delegation_admin, 100 ether);
        vm.deal(users.middleware_admin, 100 ether);
        vm.deal(users.staker_rewards_admin, 100 ether);
        vm.deal(users.insurance_fund, 100 ether);
    }
}
