// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IDelegation } from "../interfaces/IDelegation.sol";

/// @title Delegation Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for Delegation
contract DelegationStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.Delegation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DelegationStorageLocation =
        0x54b6f5557fb44acf280f59f684357ef1d216e247bba38a36a74ec93b2377e200;

    /// @dev Get Delegation storage
    /// @return $ Storage pointer
    function getDelegationStorage() internal pure returns (IDelegation.DelegationStorage storage $) {
        assembly {
            $.slot := DelegationStorageLocation
        }
    }
}
