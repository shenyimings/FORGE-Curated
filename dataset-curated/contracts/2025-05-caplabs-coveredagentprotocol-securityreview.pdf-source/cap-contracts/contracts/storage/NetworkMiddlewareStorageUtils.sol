// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { INetworkMiddleware } from "../interfaces/INetworkMiddleware.sol";

/// @title Network Middleware Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for Network Middleware
contract NetworkMiddlewareStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.NetworkMiddleware")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NetworkMiddlewareStorageLocation =
        0xb8e099bfced582503f4260023771d11f60bb84aadc54b7d0da79ce0abbf0e800;

    /// @dev Get Network Middleware storage
    /// @return $ Storage pointer
    function getNetworkMiddlewareStorage()
        internal
        pure
        returns (INetworkMiddleware.NetworkMiddlewareStorage storage $)
    {
        assembly {
            $.slot := NetworkMiddlewareStorageLocation
        }
    }
}
