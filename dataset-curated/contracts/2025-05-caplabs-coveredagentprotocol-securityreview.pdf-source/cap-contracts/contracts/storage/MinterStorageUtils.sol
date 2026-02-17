// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IMinter } from "../interfaces/IMinter.sol";

/// @title MinterStorageUtils
/// @author kexley, @capLabs
/// @notice Storage utilities for Minter contract
contract MinterStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.Minter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant MinterStorageLocation = 0x3b40995b576f8dd0a8521bba471c5346e53f6a25529b0903b82331eb1a2afe00;

    /// @notice Get Minter storage
    /// @return $ Storage pointer
    function getMinterStorage() internal pure returns (IMinter.MinterStorage storage $) {
        assembly {
            $.slot := MinterStorageLocation
        }
    }
}
