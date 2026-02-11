// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {
    ICreditManagerV3,
    CollateralCalcTask,
    CollateralDebtData
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3, MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {ACLTrait} from "@gearbox-protocol/core-v3/contracts/traits/ACLTrait.sol";
import {IPriceFeedStore} from "@gearbox-protocol/permissionless/contracts/interfaces/IPriceFeedStore.sol";
import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {CreditLogic} from "@gearbox-protocol/core-v3/contracts/libraries/CreditLogic.sol";

import {AccountMigratorBot} from "../../migration/AccountMigratorBot.sol";
import {AccountMigratorPreviewer} from "../../migration/AccountMigratorPreviewer.sol";
import {AccountMigratorAdapter30} from "../../migration/AccountMigratorAdapter30.sol";
import {AccountMigratorAdapter31} from "../../migration/AccountMigratorAdapter31.sol";
import {IAccountMigratorAdapter} from "../../interfaces/IAccountMigratorBot.sol";

import {RedstonePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/RedstonePriceFeed.sol";
import {PythPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/PythPriceFeed.sol";

import {PreviewMigrationResult} from "../../types/AccountMigrationTypes.sol";

import "forge-std/console.sol";

interface ICreditFacadeV3Old {
    function setBotPermissions(address creditAccount, address bot, uint192 permissions) external;
}

contract MigrationTestHelper is Test {
    using CreditLogic for CollateralDebtData;

    address public ioProxy;

    AccountMigratorBot public accountMigratorBot;
    AccountMigratorPreviewer public accountMigratorPreviewer;
    IAccountMigratorAdapter public accountMigratorAdapter;

    function _setUp(address _mcFactory, address _contractsRegisterOld, address _router) internal {
        ioProxy = makeAddr("ioProxy");
        accountMigratorBot = new AccountMigratorBot(_mcFactory, ioProxy, _contractsRegisterOld);
        accountMigratorPreviewer = new AccountMigratorPreviewer(address(accountMigratorBot), _router);
    }

    function _setUpAdapter(address _creditManager) internal {
        uint256 cmVersion = ICreditManagerV3(_creditManager).version();

        if (cmVersion < 3_10) {
            accountMigratorAdapter = IAccountMigratorAdapter(
                address(new AccountMigratorAdapter30(_creditManager, address(accountMigratorBot)))
            );
        } else {
            accountMigratorAdapter = IAccountMigratorAdapter(
                address(new AccountMigratorAdapter31(_creditManager, address(accountMigratorBot)))
            );
        }

        address creditConfigurator = ICreditManagerV3(_creditManager).creditConfigurator();
        address acl = ACLTrait(creditConfigurator).acl();
        address configurator = Ownable(acl).owner();

        vm.prank(configurator);
        ICreditConfiguratorV3(creditConfigurator).allowAdapter(address(accountMigratorAdapter));
    }

    function _migrateAllCreditAccounts(address oldCreditManager, address newCreditManager) internal {
        address[] memory creditAccounts = ICreditManagerV3(oldCreditManager).creditAccounts();

        for (uint256 i = 0; i < creditAccounts.length; ++i) {
            _migrateCreditAccount(creditAccounts[i], newCreditManager, false);
        }
    }

    function _migrateCreditAccount(address creditAccount, address newCreditManager, bool _revertOnFailure) internal {
        uint256 snapshot = vm.snapshot();

        _normalizeLiquidity(creditAccount, newCreditManager);

        _setBotPermissions(creditAccount);

        PreviewMigrationResult memory result =
            accountMigratorPreviewer.previewMigration(creditAccount, newCreditManager, new PriceUpdate[](0));

        if (!result.success) {
            if (_revertOnFailure) {
                revert("Migration failed");
            } else {
                emit log_named_address("Failed to migrate CA:", creditAccount);
                emit log_string("Reasons:");
                if (result.failureStates.targetHFTooLow) {
                    emit log_string("Target HF too low");
                }
                if (result.failureStates.targetSafeHFTooLow) {
                    emit log_string("Target safe HF too low");
                }
                if (result.failureStates.sourceUnderlyingIsNotCollateral) {
                    emit log_string("Source underlying is not collateral");
                }
                if (result.failureStates.migratedCollateralDoesNotExistInTarget) {
                    emit log_string("Migrated collateral does not exist in target");
                }
                if (result.failureStates.insufficientTargetQuotaLimits) {
                    emit log_string("Insufficient target quota limits");
                }
                if (result.failureStates.insufficientTargetBorrowLiquidity) {
                    emit log_string("Insufficient target borrow liquidity");
                }
                if (result.failureStates.insufficientTargetDebtLimit) {
                    emit log_string("Insufficient target debt limit");
                }
                if (result.failureStates.newTargetDebtOutOfLimits) {
                    emit log_string("New target debt out of limits");
                }
                if (result.failureStates.noPathToSourceUnderlying) {
                    emit log_string("No path to source underlying");
                }
                if (result.failureStates.cannotSwapEnoughToCoverDebt) {
                    emit log_string("Cannot swap enough to cover debt");
                }
                if (result.failureStates.sourceHasNoMigratorBotAdapter) {
                    emit log_string("Source has no migrator bot adapter");
                }
            }
            return;
        }

        vm.prank(result.migrationParams.accountOwner);
        try accountMigratorBot.migrateCreditAccount(result.migrationParams, new PriceUpdate[](0)) {}
        catch {
            if (_revertOnFailure) {
                revert("Migration failed");
            } else {
                emit log_named_address("Failed to migrate CA:", creditAccount);
                emit log_string("Reasons:");
                emit log_string("Migration previewed as successful, but reverted");
            }
        }

        vm.revertTo(snapshot);
    }

    function _setBotPermissions(address creditAccount) internal {
        address creditManager = ICreditAccountV3(creditAccount).creditManager();
        address creditFacade = ICreditManagerV3(creditManager).creditFacade();

        uint256 cmVersion = ICreditManagerV3(creditManager).version();

        address borrower = ICreditManagerV3(creditManager).getBorrowerOrRevert(creditAccount);

        if (cmVersion < 3_10) {
            uint192 permissions = accountMigratorBot.requiredPermissions();

            vm.prank(borrower);
            ICreditFacadeV3Old(creditFacade).setBotPermissions(creditAccount, address(accountMigratorBot), permissions);
        } else {
            vm.prank(borrower);

            MultiCall[] memory calls = new MultiCall[](1);
            calls[0] = MultiCall({
                target: creditFacade,
                callData: abi.encodeWithSelector(
                    ICreditFacadeV3Multicall.setBotPermissions.selector,
                    address(accountMigratorBot),
                    accountMigratorBot.requiredPermissions()
                )
            });
            vm.prank(borrower);
            ICreditFacadeV3(creditFacade).multicall(creditAccount, calls);
        }
    }

    function _warpToLatestPoolUpdate(address oldCreditManager, address newCreditManager) internal {
        address pool = ICreditManagerV3(oldCreditManager).pool();

        uint256 lastBaseInterestUpdate = IPoolV3(pool).lastBaseInterestUpdate();
        uint256 lastQuotaRevenueUpdate = IPoolV3(pool).lastQuotaRevenueUpdate();

        if (lastBaseInterestUpdate > block.timestamp) {
            vm.warp(lastBaseInterestUpdate);
        }

        if (lastQuotaRevenueUpdate > block.timestamp) {
            vm.warp(lastQuotaRevenueUpdate);
        }

        pool = ICreditManagerV3(newCreditManager).pool();

        lastBaseInterestUpdate = IPoolV3(pool).lastBaseInterestUpdate();
        lastQuotaRevenueUpdate = IPoolV3(pool).lastQuotaRevenueUpdate();

        if (lastBaseInterestUpdate > block.timestamp) {
            vm.warp(lastBaseInterestUpdate);
        }

        if (lastQuotaRevenueUpdate > block.timestamp) {
            vm.warp(lastQuotaRevenueUpdate);
        }
    }

    function _normalizeLiquidity(address creditAccount, address newCreditManager) internal {
        address oldCreditManager = ICreditAccountV3(creditAccount).creditManager();

        _warpToLatestPoolUpdate(oldCreditManager, newCreditManager);

        CollateralDebtData memory cdd =
            ICreditManagerV3(oldCreditManager).calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_ONLY);

        uint256 totalDebt = _getEquivalent(
            newCreditManager,
            ICreditManagerV3(oldCreditManager).underlying(),
            ICreditManagerV3(newCreditManager).underlying(),
            cdd.calcTotalDebt()
        );

        if (totalDebt == 0) {
            return;
        }

        address pool = ICreditManagerV3(newCreditManager).pool();

        uint256 remainingBorrowable = IPoolV3(pool).creditManagerBorrowable(newCreditManager);

        if (remainingBorrowable < 2 * totalDebt) {
            uint256 depositAmount = 2 * totalDebt;
            {
                if (
                    IPoolV3(pool).expectedLiquidity() != 0
                        && IPoolV3(pool).availableLiquidity() < IPoolV3(pool).expectedLiquidity()
                ) {
                    uint256 utilization = 1e18
                        * (IPoolV3(pool).expectedLiquidity() - IPoolV3(pool).availableLiquidity())
                        / IPoolV3(pool).expectedLiquidity();
                    if (utilization > 85 * 1e18 / 100) {
                        depositAmount += IPoolV3(pool).expectedLiquidity() * utilization / (75 * 1e18 / 100)
                            - IPoolV3(pool).expectedLiquidity();
                    }
                }
            }

            address underlying = IPoolV3(pool).asset();

            deal(underlying, pool, depositAmount);

            address acl = ACLTrait(pool).acl();
            address configurator = Ownable(acl).owner();

            uint256 currentLimit = IPoolV3(pool).creditManagerDebtLimit(newCreditManager);
            vm.prank(configurator);
            IPoolV3(pool).setCreditManagerDebtLimit(newCreditManager, currentLimit + depositAmount);
        }
    }

    function _getEquivalent(address newCreditManager, address oldUnderlying, address newUnderlying, uint256 amount)
        internal
        view
        returns (uint256)
    {
        address priceOracle = ICreditManagerV3(newCreditManager).priceOracle();

        return IPriceOracleV3(priceOracle).convert(amount, oldUnderlying, newUnderlying);
    }

    function _updatePriceFeeds(address _creditManager) internal {
        address creditFacade = ICreditManagerV3(_creditManager).creditFacade();
        address priceFeedStore = ICreditFacadeV3(creditFacade).priceFeedStore();

        address[] memory updatableFeeds = IPriceFeedStore(priceFeedStore).getUpdatablePriceFeeds();

        for (uint256 i = 0; i < updatableFeeds.length; ++i) {
            _refreshUpdatablePriceFeed(updatableFeeds[i]);
        }
    }

    function _refreshUpdatablePriceFeed(address priceFeed) internal {
        bytes32 pfType = IPriceFeed(priceFeed).contractType();

        if (pfType == "PRICE_FEED::REDSTONE") {
            uint256 initialTS = block.timestamp;

            bytes32 dataFeedId = RedstonePriceFeed(priceFeed).dataFeedId();
            uint8 signersThreshold = RedstonePriceFeed(priceFeed).getUniqueSignersThreshold();

            bytes memory payload =
                _getRedstonePayload(bytes32ToString((dataFeedId)), Strings.toString(signersThreshold));

            if (payload.length == 0) return;

            (uint256 expectedPayloadTimestamp,) = abi.decode(payload, (uint256, bytes));

            if (expectedPayloadTimestamp > block.timestamp) {
                vm.warp(expectedPayloadTimestamp);
            }

            try RedstonePriceFeed(priceFeed).updatePrice(payload) {} catch {}

            vm.warp(initialTS);
        } else if (pfType == "PRICE_FEED::PYTH") {
            uint256 initialTS = block.timestamp;

            address payable pf = payable(priceFeed);
            bytes32 priceFeedId = PythPriceFeed(pf).priceFeedId();

            bytes memory payload = _getPythPayload(Strings.toHexString(uint256(priceFeedId)));

            (uint256 expectedPayloadTimestamp,) = abi.decode(payload, (uint256, bytes));

            if (expectedPayloadTimestamp > block.timestamp) {
                vm.warp(expectedPayloadTimestamp);
            }

            try PythPriceFeed(pf).updatePrice(payload) {} catch {}

            vm.warp(initialTS);
        } else {
            return;
        }
    }

    function _getPythPayload(string memory priceFeedId) internal returns (bytes memory) {
        string[] memory args = new string[](4);
        args[0] = "npx";
        args[1] = "ts-node";
        args[2] = "./script/pyth.ts";
        args[3] = priceFeedId;

        return vm.ffi(args);
    }

    function _getRedstonePayload(string memory dataFeedId, string memory signersThreshold)
        internal
        returns (bytes memory)
    {
        string[2] memory dataServiceIds = ["redstone-primary-prod", "redstone-arbitrum-prod"];

        for (uint256 i = 0; i < dataServiceIds.length; ++i) {
            string[] memory args = new string[](6);
            args[0] = "npx";
            args[1] = "ts-node";
            args[2] = "./script/redstone.ts";
            args[3] = dataServiceIds[i];
            args[4] = dataFeedId;
            args[5] = signersThreshold;

            try vm.ffi(args) returns (bytes memory response) {
                return response;
            } catch {}
        }

        return "";
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
