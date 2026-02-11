// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarginState} from "../types/MarginState.sol";

/// @notice Interface for all interest-fee related functions in the pool manager
interface IMarginBase {
    error Unauthorized();

    event MarginControllerUpdated(address indexed marginController);

    /// @notice Emitted when the rate state is updated
    /// @param newMarginState The new rate state being set
    /// @dev This event is emitted when the rate state is updated, allowing external observers to
    event MarginStateUpdated(MarginState indexed newMarginState);

    /// @notice Sets the rate state for interest fees
    /// @param newMarginState The new rate state to set
    /// @dev This function allows the owner to update the rate state, which is used to
    /// calculate interest fees. It emits a MarginStateUpdated event upon success.
    /// @dev Only the owner can call this function.
    /// @dev Reverts if the caller is not the owner.
    function setMarginState(MarginState newMarginState) external;

    function marginState() external view returns (MarginState);

    function marginController() external view returns (address);
}
