// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IStateSerializer} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IStateSerializer.sol";
import {IBot} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IBot.sol";
import {IAdapter} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IAdapter.sol";

import {PriceUpdate} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeedStore.sol";
import {MigrationParams, PreviewMigrationResult, PhantomTokenOverride} from "../types/AccountMigrationTypes.sol";

interface IAccountMigratorPreviewer is IVersion, IStateSerializer {
    function previewMigration(
        address sourceCreditAccount,
        address targetCreditManager,
        PriceUpdate[] memory priceUpdates
    ) external returns (PreviewMigrationResult memory result);
}

interface IAccountMigratorBot is IBot {
    function migrateCreditAccount(MigrationParams memory params, PriceUpdate[] memory priceUpdates) external;

    function migrate(MigrationParams memory params) external;

    function phantomTokenOverrides(address phantomToken) external view returns (PhantomTokenOverride memory);
}

interface IAccountMigratorAdapter is IAdapter {
    function unlock() external;
    function lock() external;
    function migrate(MigrationParams memory params) external;
}
