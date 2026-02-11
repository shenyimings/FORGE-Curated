// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Velora registry of valid Augustus contracts
/// @dev https://github.com/paraswap/augustus-v5/blob/d297477b8fc7be65c337b0cf2bc21f4f7f925b68/contracts/IAugustusRegistry.sol
interface IAugustusRegistry {
    function isValidAugustus(address augustus) external view returns (bool);
}
