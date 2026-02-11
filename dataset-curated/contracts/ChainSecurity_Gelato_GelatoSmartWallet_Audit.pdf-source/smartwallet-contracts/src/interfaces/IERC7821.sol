// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// https://eips.ethereum.org/EIPS/eip-7821
interface IERC7821 {
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    function execute(bytes32 mode, bytes calldata executionData) external payable;

    function supportsExecutionMode(bytes32 mode) external view returns (bool);
}
