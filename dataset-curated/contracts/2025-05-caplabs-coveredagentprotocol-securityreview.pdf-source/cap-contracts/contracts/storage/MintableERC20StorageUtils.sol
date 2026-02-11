// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IMintableERC20 } from "../interfaces/IMintableERC20.sol";

/// @title Mintable ERC20 Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for mintable ERC20
abstract contract MintableERC20StorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.MintableERC20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MintableERC20StorageLocation =
        0xb6fbed03401708c99484f1851d78d51d50311db3f9957176b94dc0ef6e099a00;

    /// @dev Get mintable ERC20 storage
    /// @return $ Storage pointer
    function getMintableERC20Storage() internal pure returns (IMintableERC20.MintableERC20Storage storage $) {
        assembly {
            $.slot := MintableERC20StorageLocation
        }
    }
}
