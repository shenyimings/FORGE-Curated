// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {MigrationTestHelper} from "./MigrationTestHelper.sol";
import {MarketCloner} from "./cloners/MarketCloner.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";

import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {IConvexV1BaseRewardPoolAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/interfaces/convex/IConvexV1BaseRewardPoolAdapter.sol";
import {IStakingRewardsAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/interfaces/sky/IStakingRewardsAdapter.sol";

address constant stkcvxRLUSD_USDC = 0x444FA0ffb033265591895b66c81c2e5fF606E097;
address constant stkcvxllamathena = 0x72eD19788Bce2971A5ed6401662230ee57e254B7;
address constant stkUSDS = 0xcB5D10A57Aeb622b92784D53F730eE2210ab370E;

address constant cvxRLUSD_USDC = 0xBd5D4c539B3773086632416A4EC8ceF57c945319;
address constant cvxllamathena = 0x237926E55f9deee89833a42dEb92d3a6970850B4;
address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

contract CloneMigrationTest is MigrationTestHelper, MarketCloner {
    function setUp() public {
        address mcFactory = vm.envOr("MARKET_CONFIGURATOR_FACTORY", address(0));
        address contractsRegisterOld = vm.envOr("CONTRACTS_REGISTER_OLD", address(0));
        address addressProvider = vm.envOr("ADDRESS_PROVIDER", address(0));
        address router = vm.envOr("ROUTER", address(0));

        if (mcFactory == address(0) || addressProvider == address(0) || router == address(0)) {
            revert("ForkMigrationTest: missing environment variables");
        }

        _setUp(mcFactory, contractsRegisterOld, router);
        _setUpCloner(mcFactory, addressProvider);
    }

    function _setUpPTOverrides() internal {
        vm.startPrank(ioProxy);
        if (_getNewPhantomToken(stkcvxRLUSD_USDC) != address(0)) {
            accountMigratorBot.setPhantomTokenOverride(
                stkcvxRLUSD_USDC,
                _getNewPhantomToken(stkcvxRLUSD_USDC),
                cvxRLUSD_USDC,
                abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdrawDiff, (0, false))
            );
        }

        if (_getNewPhantomToken(stkcvxllamathena) != address(0)) {
            accountMigratorBot.setPhantomTokenOverride(
                stkcvxllamathena,
                _getNewPhantomToken(stkcvxllamathena),
                cvxllamathena,
                abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdrawDiff, (0, false))
            );
        }

        if (_getNewPhantomToken(stkUSDS) != address(0)) {
            accountMigratorBot.setPhantomTokenOverride(
                stkUSDS, _getNewPhantomToken(stkUSDS), USDS, abi.encodeCall(IStakingRewardsAdapter.withdrawDiff, (0))
            );
        }
        vm.stopPrank();
    }

    function test_migrateCreditAccountsToClonedMarket() public {
        address oldMarket = vm.envOr("OLD_MARKET", address(0));

        _cloneMarket(oldMarket);
        _setUpPTOverrides();

        address[] memory oldCreditManagers = IPoolV3(oldMarket).creditManagers();

        for (uint256 i = 0; i < oldCreditManagers.length; ++i) {
            address oldCreditManager = oldCreditManagers[i];
            address newCreditManager = oldToNewCreditManager[oldCreditManager];

            _setUpAdapter(oldCreditManager);

            _migrateAllCreditAccounts(oldCreditManager, newCreditManager);
        }
    }

    function test_migrateAccountToClonedMarket() public {
        address oldCreditAccount = vm.envOr("OLD_CREDIT_ACCOUNT", address(0));

        address oldCreditManager = ICreditAccountV3(oldCreditAccount).creditManager();
        address oldPool = ICreditManagerV3(oldCreditManager).pool();

        _cloneMarket(oldPool);

        _setUpPTOverrides();

        _setUpAdapter(oldCreditManager);

        address newCreditManager = oldToNewCreditManager[oldCreditManager];

        _migrateCreditAccount(oldCreditAccount, newCreditManager, true);
    }
}
