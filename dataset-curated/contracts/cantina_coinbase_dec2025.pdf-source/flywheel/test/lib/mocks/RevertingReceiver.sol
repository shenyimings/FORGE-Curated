// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title RevertingReceiver
/// @notice A contract that reverts on receiving tokens or ETH
contract RevertingReceiver {
    receive() external payable {
        revert("Cannot receive ETH");
    }

    fallback() external payable {
        revert("Cannot receive tokens");
    }
}
