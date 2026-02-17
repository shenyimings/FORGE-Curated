// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IFeeAuction } from "../interfaces/IFeeAuction.sol";

/// @title Fee Auction Storage Utils
/// @author kexley, @capLabs
/// @notice Storage utilities for fee auction
contract FeeAuctionStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.FeeAuction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FeeAuctionStorageLocation =
        0xbbabf7dab1936c7afe15748adafbe56186d0b57f14b5bc3e6f8d57aad0236100;

    /// @dev Get fee auction storage
    /// @return $ Storage pointer
    function get() internal pure returns (IFeeAuction.FeeAuctionStorage storage $) {
        assembly {
            $.slot := FeeAuctionStorageLocation
        }
    }
}
