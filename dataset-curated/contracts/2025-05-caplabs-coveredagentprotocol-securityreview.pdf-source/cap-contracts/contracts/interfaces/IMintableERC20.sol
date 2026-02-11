// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title IMintableERC20
/// @author kexley, @capLabs
/// @notice Interface for mintable ERC20
interface IMintableERC20 {
    /// @custom:storage-location erc7201:cap.storage.MintableERC20
    struct MintableERC20Storage {
        string name;
        string symbol;
        uint8 decimals;
        mapping(address => uint256) balances;
        uint256 totalSupply;
    }

    /// @dev Operation not supported
    error OperationNotSupported();
}
