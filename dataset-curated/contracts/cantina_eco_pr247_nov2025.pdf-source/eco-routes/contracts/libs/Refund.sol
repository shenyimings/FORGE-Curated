// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title Refund
 * @notice Library for handling native token refunds
 * @dev Provides common refund functionality for contracts
 */
library Refund {
    /**
     * @notice Refunds all remaining native tokens to the sender
     * @dev Does not revert on failure to prevent griefing attacks
     * @return success Whether the refund was successful
     */
    function excessNative() internal returns (bool success) {
        uint256 balance = address(this).balance;
        if (balance == 0) return true;

        (success, ) = payable(msg.sender).call{value: balance}("");
    }
}
