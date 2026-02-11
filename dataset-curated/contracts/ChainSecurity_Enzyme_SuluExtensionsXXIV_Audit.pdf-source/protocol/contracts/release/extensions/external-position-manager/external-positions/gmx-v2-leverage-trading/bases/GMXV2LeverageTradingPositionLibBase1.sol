// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

/// @title GMXV2LeverageTradingPositionLibBase1 Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A persistent contract containing all required storage variables and
/// required functions for a GMXV2LeverageTradingPositionLib implementation
/// @dev DO NOT EDIT CONTRACT. If new events or storage are necessary, they should be added to
/// a numbered GMXV2LeverageTradingPositionLibBaseXXX that inherits the previous base.
/// e.g., `GMXV2LeverageTradingPositionLibBase2 is GMXV2LeverageTradingPositionLibBase1`
abstract contract GMXV2LeverageTradingPositionLibBase1 {
    event CallbackContractSet(address market);

    event ClaimableCollateralAdded(bytes32 claimableCollateralKey, address token, address market, uint256 timeKey);

    event ClaimableCollateralRemoved(bytes32 claimableCollateralKey);

    event TrackedAssetAdded(address asset);

    event TrackedAssetsCleared();

    event TrackedMarketAdded(address market);

    event TrackedMarketRemoved(address market);

    /// @dev Keeps track of whether a particular market has been assigned the callback contract (i.e. the EP)
    mapping(address => bool) internal marketToIsCallbackContractSet;

    /// @dev Tracked assets that are receivable by the EP through actions that are triggered externally (e.g. order cancellations/liquidations)
    address[] internal trackedAssets;

    /// @dev Tracked markets that the EP has interacted with. Necessary for tracking funding fees, which open orders can accrue.
    address[] internal trackedMarkets;

    /// @dev Keys to keep track of collateral claimable by the EP. Collateral can become claimable through order decreases
    bytes32[] internal claimableCollateralKeys;

    struct ClaimableCollateralInfo {
        address token;
        address market;
        uint256 timeKey;
    }

    /// @dev Additional information pertaining to the claimable collateral. Necessary for retrieving total claimable and claimed amounts
    mapping(bytes32 => ClaimableCollateralInfo) internal claimableCollateralKeyToClaimableCollateralInfo;
}
