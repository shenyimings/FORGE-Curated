// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IInterestDebtToken } from "../interfaces/IInterestDebtToken.sol";

/// @title Interest Debt Token Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for interest debt token
contract InterestDebtTokenStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.InterestDebt")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant InterestDebtTokenStorageLocation =
        0x162fe0b309d5cb2212ec304072bcf3222b3d6f4b4391048e3b69d42273fdd600;

    /// @dev Get interest debt token storage
    /// @return $ Storage pointer
    function getInterestDebtTokenStorage()
        internal
        pure
        returns (IInterestDebtToken.InterestDebtTokenStorage storage $)
    {
        assembly {
            $.slot := InterestDebtTokenStorageLocation
        }
    }
}
