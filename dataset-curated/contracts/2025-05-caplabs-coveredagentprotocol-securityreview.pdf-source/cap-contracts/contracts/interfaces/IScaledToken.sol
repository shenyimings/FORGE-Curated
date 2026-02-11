// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Scaled Token Interface
/// @author kexley, @capLabs
/// @notice Interface for the scaled token that distributes yield accrued from agents borrowing underlying assets
interface IScaledToken is IERC20 {
    /// @custom:storage-location erc7201:cap.storage.ScaledToken
    struct ScaledTokenStorage {
        mapping(address => uint256) balance;
        mapping(address => uint256) scaledBalance;
        mapping(address => uint256) storedIndex;
        uint256 totalSupply;
        uint256 scaledTotalSupply;
    }

    /// @dev Invalid mint amount
    error InvalidMintAmount();

    /// @dev Invalid burn amount
    error InvalidBurnAmount();
}
