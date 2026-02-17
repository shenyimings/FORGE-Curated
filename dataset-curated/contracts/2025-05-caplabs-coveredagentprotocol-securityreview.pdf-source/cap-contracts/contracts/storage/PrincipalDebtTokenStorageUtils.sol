// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IPrincipalDebtToken } from "../interfaces/IPrincipalDebtToken.sol";

/// @title Principal Debt Token Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for principal debt token
contract PrincipalDebtTokenStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.PrincipalDebt")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PrincipalDebtTokenStorageLocation =
        0xfe61eb39a03fa9d2a68f7a98d61b3fb035d91299516f39d49c66c6d5d3d0c100;

    /// @dev Get principal debt token storage
    /// @return $ Storage pointer
    function getPrincipalDebtTokenStorage()
        internal
        pure
        returns (IPrincipalDebtToken.PrincipalDebtTokenStorage storage $)
    {
        assembly {
            $.slot := PrincipalDebtTokenStorageLocation
        }
    }
}
