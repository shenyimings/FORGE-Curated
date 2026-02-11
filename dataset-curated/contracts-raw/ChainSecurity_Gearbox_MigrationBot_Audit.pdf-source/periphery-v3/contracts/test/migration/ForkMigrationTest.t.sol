// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {MigrationTestHelper} from "./MigrationTestHelper.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";

contract ForkMigrationTest is MigrationTestHelper {
    function setUp() public {
        address mcFactory = vm.envOr("MARKET_CONFIGURATOR_FACTORY", address(0));
        address contractsRegisterOld = vm.envOr("CONTRACTS_REGISTER_OLD", address(0));
        address router = vm.envOr("ROUTER", address(0));

        if (mcFactory == address(0) || contractsRegisterOld == address(0) || router == address(0)) {
            revert("ForkMigrationTest: missing environment variables");
        }

        _setUp(mcFactory, contractsRegisterOld, router);
    }

    function test_migrateAllCreditAccounts() public {
        address oldCreditManager = vm.envOr("OLD_CREDIT_MANAGER", address(0));
        address newCreditManager = vm.envOr("NEW_CREDIT_MANAGER", address(0));

        if (oldCreditManager == address(0) || newCreditManager == address(0)) {
            revert("ForkMigrationTest: missing environment variables");
        }

        _setUpAdapter(oldCreditManager);
        _updatePriceFeeds(newCreditManager);

        _migrateAllCreditAccounts(oldCreditManager, newCreditManager);
    }

    function test_migrateCreditAccount() public {
        address oldCreditAccount = vm.envOr("OLD_CREDIT_ACCOUNT", address(0));
        address newCreditManager = vm.envOr("NEW_CREDIT_MANAGER", address(0));

        if (oldCreditAccount == address(0) || newCreditManager == address(0)) {
            revert("ForkMigrationTest: missing environment variables");
        }

        address oldCreditManager = ICreditAccountV3(oldCreditAccount).creditManager();

        _setUpAdapter(oldCreditManager);
        _updatePriceFeeds(newCreditManager);

        _migrateCreditAccount(oldCreditAccount, newCreditManager, true);
    }
}
