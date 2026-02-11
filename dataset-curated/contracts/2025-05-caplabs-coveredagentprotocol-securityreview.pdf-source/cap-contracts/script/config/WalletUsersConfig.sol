// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { UsersConfig } from "../../contracts/deploy/interfaces/DeployConfigs.sol";
import { WalletUtils } from "../../contracts/deploy/utils/WalletUtils.sol";

contract WalletUsersConfig is WalletUtils {
    function _getUsersConfig() internal view returns (UsersConfig memory users) {
        users = UsersConfig({
            deployer: getWalletAddress(),
            access_control_admin: getWalletAddress(),
            address_provider_admin: getWalletAddress(),
            oracle_admin: getWalletAddress(),
            rate_oracle_admin: getWalletAddress(),
            vault_config_admin: getWalletAddress(),
            lender_admin: getWalletAddress(),
            fee_auction_admin: getWalletAddress(),
            delegation_admin: getWalletAddress(),
            middleware_admin: getWalletAddress(),
            staker_rewards_admin: getWalletAddress()
        });
    }
}
