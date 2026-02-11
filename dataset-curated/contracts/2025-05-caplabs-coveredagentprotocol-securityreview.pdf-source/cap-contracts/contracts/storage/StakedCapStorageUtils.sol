// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IStakedCap } from "../interfaces/IStakedCap.sol";

/// @title StakedCap Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for StakedCap control
abstract contract StakedCapStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.StakedCap")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StakedCapStorageLocation =
        0xc3a6ec7b30f1d79063d00dcbb5942b226b77fe48a28f1a19018e7d1f70fd7600;

    /// @dev Get StakedCap storage
    /// @return $ Storage pointer
    function getStakedCapStorage() internal pure returns (IStakedCap.StakedCapStorage storage $) {
        assembly {
            $.slot := StakedCapStorageLocation
        }
    }
}
