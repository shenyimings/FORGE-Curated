// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IRestakerDebtToken } from "../interfaces/IRestakerDebtToken.sol";

/// @title Restaker Debt Token Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for restaker debt token
contract RestakerDebtTokenStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.RestakerDebt")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RestakerDebtTokenStorageLocation =
        0x2dd1dd482e00c02bf87ac740376f032edca8a52ab1bbd273a66a2eb62e294e00;

    /// @dev Get restaker debt token storage
    /// @return $ Storage pointer
    function getRestakerDebtTokenStorage()
        internal
        pure
        returns (IRestakerDebtToken.RestakerDebtTokenStorage storage $)
    {
        assembly {
            $.slot := RestakerDebtTokenStorageLocation
        }
    }
}
