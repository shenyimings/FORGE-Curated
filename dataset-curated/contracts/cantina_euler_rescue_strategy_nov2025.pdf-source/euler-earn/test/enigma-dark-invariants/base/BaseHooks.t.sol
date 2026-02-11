// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {ProtocolAssertions} from "./ProtocolAssertions.t.sol";

// Test Contracts
import {SpecAggregator} from "../SpecAggregator.t.sol";

/// @title BaseHooks
/// @notice Contains common logic for all hooks
/// @dev inherits all suite assertions since per-action assertions are implemented in the handlers
/// @dev inherits SpecAggregator
contract BaseHooks is ProtocolAssertions, SpecAggregator {
    /// @dev track the asset delta of the action, deposit/mint is positive, withdraw/redeem is negative
    int256 public actionAssetDelta;

    /// @dev set the action asset delta, called at:
    /// - depositEEV
    /// - mintEEV
    /// - withdrawEEV
    /// - redeemEEV
    function _setActionAssetDelta(int256 _actionAssetDelta) internal {
        actionAssetDelta = _actionAssetDelta;
    }

    /// @dev reset the action asset delta, called at:
    /// - after the action
    function _resetActionAssetDelta() internal {
        actionAssetDelta = 0;
    }
}
