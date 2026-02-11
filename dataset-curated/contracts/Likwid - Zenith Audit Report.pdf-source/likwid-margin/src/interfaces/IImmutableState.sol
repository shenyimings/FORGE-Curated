// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "./IVault.sol";

/// @title Interface for ImmutableState
interface IImmutableState {
    /// @notice The vault contract
    function vault() external view returns (IVault);
}
