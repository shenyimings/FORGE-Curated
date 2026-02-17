// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IAccess } from "../interfaces/IAccess.sol";

/// @title Access Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for access control
contract AccessStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.Access")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AccessStorageLocation = 0xb413d65cb88f23816c329284a0d3eb15a99df7963ab7402ade4c5da22bff6b00;

    /// @dev Get access storage
    /// @return $ Storage pointer
    function getAccessStorage() internal pure returns (IAccess.AccessStorage storage $) {
        assembly {
            $.slot := AccessStorageLocation
        }
    }
}
