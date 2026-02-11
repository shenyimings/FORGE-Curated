// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title IAccess
/// @author kexley, @capLabs
/// @notice Interface for Access contract
interface IAccess {
    /// @custom:storage-location erc7201:cap.storage.Access
    struct AccessStorage {
        address accessControl;
    }
}
