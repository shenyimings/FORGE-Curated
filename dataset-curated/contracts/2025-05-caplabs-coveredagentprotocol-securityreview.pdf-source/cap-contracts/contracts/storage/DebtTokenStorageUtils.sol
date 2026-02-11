// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IDebtToken } from "../interfaces/IDebtToken.sol";

/// @title Debt Token Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for debt token
abstract contract DebtTokenStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.DebtToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DebtTokenStorageLocation =
        0xf23a45dc65f14b1e5fe39f1163c383ff2dcba1153a83755b36cb0d5d51f3c600;

    /// @dev Get debt token storage
    /// @return $ Storage pointer
    function getDebtTokenStorage() internal pure returns (IDebtToken.DebtTokenStorage storage $) {
        assembly {
            $.slot := DebtTokenStorageLocation
        }
    }
}
