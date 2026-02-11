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
    Deposit,
    Withdraw
}

/// @dev Struct that contains all data related to a LeverageToken action
struct ActionData {
    /// @dev Amount of collateral added or withdrawn
    uint256 collateral;
    /// @dev Amount of debt borrowed or repaid
    uint256 debt;
    /// @dev Amount of equity added or withdrawn before fees, denominated in collateral asset
    uint256 equity;
    /// @dev Amount of shares minted or burned to user
    uint256 shares;
    /// @dev Fee charged for the action to the leverage token, denominated in collateral asset
    uint256 tokenFee;
    /// @dev Fee charged for the action to the treasury, denominated in collateral asset
    uint256 treasuryFee;
}

/// @dev Struct containing auction parameters
struct Auction {
    /// @dev Whether the LeverageToken is over-collateralized
    bool isOverCollateralized;
    /// @dev Timestamp when the auction started
    uint256 startTimestamp;
    /// @dev Timestamp when the auction ends/ended
    uint256 endTimestamp;
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
    /// @dev Fee for deposit action
    uint256 depositTokenFee;
    /// @dev Fee for withdraw action, defined as a percentage
    uint256 withdrawTokenFee;
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
    /// @dev LeverageToken to perform the action on
    ILeverageToken leverageToken;
    /// @dev Type of action to perform
    ActionType actionType;
    /// @dev Amount to perform the action with
    uint256 amount;
}

/// @dev Struct that contains all data related to a token transfer
struct TokenTransfer {
    /// @dev Token to transfer
    address token;
    /// @dev Amount to transfer
    uint256 amount;
}
