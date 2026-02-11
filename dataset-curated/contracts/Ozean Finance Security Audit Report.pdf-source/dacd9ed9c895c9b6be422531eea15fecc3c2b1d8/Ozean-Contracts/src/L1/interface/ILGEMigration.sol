// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @title  LGE Migration Interface
/// @notice Interface for the LGE Migrator contract to move LGE assets onto Ozean mainnet.
interface ILGEMigration {
    function migrate(address _l2Destination, address[] calldata _tokens, uint256[] calldata _amounts) external;
}
