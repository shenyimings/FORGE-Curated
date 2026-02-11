// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {AbstractAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/AbstractAdapter.sol";
import {IAccountMigratorAdapter} from "../interfaces/IAccountMigratorBot.sol";
import {MigrationParams, MigratedCollateral} from "../types/AccountMigrationTypes.sol";

abstract contract AccountMigratorAdapter is AbstractAdapter {
    /// @dev Legacy adapter type parameter, for compatibility with 3.0 contracts
    uint8 public constant _gearboxAdapterType = 0;

    /// @dev Legacy adapter version parameter, for compatibility with 3.0 contracts
    uint16 public constant _gearboxAdapterVersion = 3_10;

    bytes32 public constant override contractType = "ADAPTER::ACCOUNT_MIGRATOR";
    uint256 public constant override version = 3_10;

    /// @dev Whether tha adapter is locked. The adapter should only be interactable when unlocked from the migrator bot,
    ///      as the `migrate` function is fairly dangerous.
    bool public locked = true;

    modifier onlyMigratorBot() {
        if (msg.sender != targetContract) {
            revert("MigratorAdapter: caller is not the migrator bot");
        }
        _;
    }

    modifier whenUnlocked() {
        if (locked) {
            revert("MigratorAdapter: adapter is locked");
        }
        _;
    }

    constructor(address _creditManager, address _migratorBot) AbstractAdapter(_creditManager, _migratorBot) {}

    /// @dev Internal function to migrate collaterals to a new credit account
    function _migrate(MigrationParams memory params) internal {
        _approveTokens(params.migratedCollaterals, type(uint256).max);
        _execute(msg.data);
        _approveTokens(params.migratedCollaterals, 0);
    }

    function _approveTokens(MigratedCollateral[] memory tokens, uint256 amount) internal {
        uint256 len = tokens.length;

        for (uint256 i = 0; i < len; i++) {
            address token = tokens[i].phantomTokenParams.isPhantomToken
                ? tokens[i].phantomTokenParams.underlying
                : tokens[i].collateral;
            _approveToken(token, amount);
        }
    }

    function lock() external onlyMigratorBot {
        locked = true;
    }

    function unlock() external onlyMigratorBot {
        locked = false;
    }

    /// @notice Serialized adapter parameters
    function serialize() external view returns (bytes memory serializedData) {
        serializedData = abi.encode(creditManager, targetContract);
    }
}
