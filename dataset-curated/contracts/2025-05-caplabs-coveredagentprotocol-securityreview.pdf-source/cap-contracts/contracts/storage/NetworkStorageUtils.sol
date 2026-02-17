// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { INetwork } from "../interfaces/INetwork.sol";

/// @title Network Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for Network
contract NetworkStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.Network")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NetworkStorageLocation = 0xec23e17a5ca56acc6967467b8c4a73cf6149bcd343f3f3cbe7c4e19c4d822b00;

    /// @dev Get Network storage
    /// @return $ Storage pointer
    function getNetworkStorage() internal pure returns (INetwork.NetworkStorage storage $) {
        assembly {
            $.slot := NetworkStorageLocation
        }
    }
}
