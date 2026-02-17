// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IFractionalReserve } from "../interfaces/IFractionalReserve.sol";

/// @title FractionalReserveStorageUtils
/// @author kexley, @capLabs
/// @notice Storage utilities for Fractional Reserve contract
contract FractionalReserveStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.FractionalReserve")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant FractionalReserveStorageLocation =
        0x5c48f30a22a9811126b69b5adcaabfc5ae0a83b6493e1b31e09dc579923ad100;

    /// @notice Get FractionalReserve storage
    /// @return $ Storage pointer
    function getFractionalReserveStorage()
        internal
        pure
        returns (IFractionalReserve.FractionalReserveStorage storage $)
    {
        assembly {
            $.slot := FractionalReserveStorageLocation
        }
    }
}
