// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";

/// @dev Enum defining internal actions that a LendingAdapter can perform on a lending pool
enum ActionType {
    AddCollateral,
    RemoveCollateral,
    Borrow,
    Repay
}

/// @dev Enum defining actions that users can perform on a LeverageToken
enum ExternalAction {
    Mint,
    Redeem
}

/// @dev Struct that contains all data related to a LeverageToken action
struct ActionData {
    /// @dev Amount of collateral added or withdrawn
    uint256 collateral;
    /// @dev Amount of debt borrowed or repaid
    uint256 debt;
    /// @dev Amount of shares the user gains or loses for the action (whether that be via minting, burning, or fees)
    uint256 shares;
    /// @dev Fee charged for the action to the leverage token, denominated in shares
    uint256 tokenFee;
    /// @dev Fee charged for the action to the treasury, denominated in shares
    uint256 treasuryFee;
}

/// @dev Struct containing auction parameters
struct Auction {
    /// @dev Whether the LeverageToken is over-collateralized
    bool isOverCollateralized;
    /// @dev Timestamp when the auction started
    uint120 startTimestamp;
    /// @dev Timestamp when the auction ends/ended
    uint120 endTimestamp;
}

/// @dev Struct that contains the base LeverageToken config stored in LeverageManager
struct BaseLeverageTokenConfig {
    /// @dev LendingAdapter for the LeverageToken
    ILendingAdapter lendingAdapter;
    /// @dev RebalanceAdapter for the LeverageToken
    IRebalanceAdapterBase rebalanceAdapter;
}

/// @dev Struct that contains the entire LeverageToken config
struct LeverageTokenConfig {
    /// @dev LendingAdapter for the LeverageToken
    ILendingAdapter lendingAdapter;
    /// @dev RebalanceAdapter for the LeverageToken
    IRebalanceAdapterBase rebalanceAdapter;
    /// @dev Fee for mint action, defined as a percentage
    uint256 mintTokenFee;
    /// @dev Fee for redeem action, defined as a percentage
    uint256 redeemTokenFee;
}

/// @dev Struct that contains all data describing the state of a LeverageToken
struct LeverageTokenState {
    /// @dev Collateral denominated in debt asset
    uint256 collateralInDebtAsset;
    /// @dev Debt
    uint256 debt;
    /// @dev Equity denominated in debt asset
    uint256 equity;
    /// @dev Collateral ratio on 8 decimals
    uint256 collateralRatio;
}

/// @dev Struct that contains all data related to a rebalance action
struct RebalanceAction {
    /// @dev Type of action to perform
    ActionType actionType;
    /// @dev Amount to perform the action with
    uint256 amount;
}
