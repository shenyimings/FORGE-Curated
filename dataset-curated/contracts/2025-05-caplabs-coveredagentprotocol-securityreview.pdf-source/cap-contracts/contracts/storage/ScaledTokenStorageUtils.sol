// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IScaledToken } from "../interfaces/IScaledToken.sol";

/// @title ScaledToken Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for ScaledToken
abstract contract ScaledTokenStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.ScaledToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ScaledTokenStorageLocation =
        0x3e9197df6de91125667a616e29706be52c05ace5482bc6659579e06a73af7500;

    /// @dev Get ScaledToken storage
    /// @return $ Storage pointer
    function getScaledTokenStorage() internal pure returns (IScaledToken.ScaledTokenStorage storage $) {
        assembly {
            $.slot := ScaledTokenStorageLocation
        }
    }
}
