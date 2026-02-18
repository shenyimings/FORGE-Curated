// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {Trade, TradeType} from "./ITradingModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

struct TradeParams {
    uint256 tradeAmount;
    uint16 dexId;
    TradeType tradeType;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

/// @notice Deposit parameters
struct DepositParams {
    /// @notice min pool claim for slippage control
    uint256 minPoolClaim;
    /// @notice DepositTradeParams or empty (single-sided entry)
    TradeParams[] depositTrades;
}

/// @notice Redeem parameters
struct RedeemParams {
    /// @notice min amounts for slippage control
    uint256[] minAmounts;
    /// @notice Redemption trades or empty (single-sided exit)
    TradeParams[] redemptionTrades;
}

struct WithdrawParams {
    uint256[] minAmounts;
    bytes[] withdrawData;
}

/// @dev Internal library for single-sided LPs, used to reduce the bytecode size of the main contract
interface ILPLib {

    /// @dev Approves the tokens needed for the pool, only called once during initialization
    function initialApproveTokens() external;

    /// @dev Joins the pool and stakes the tokens
    function joinPoolAndStake(uint256[] memory amounts, uint256 minPoolClaim) external;

    /// @dev Unstakes and exits the pool
    function unstakeAndExitPool(uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided) external returns (uint256[] memory exitBalances);

    /// @dev Gets the value of all pending withdrawals
    function getWithdrawRequestValue(address account, address asset, uint256 shares) external view returns (uint256 totalValue);

    /// @dev Finalizes a withdraw request and redeems the shares
    function finalizeAndRedeemWithdrawRequest(
        address sharesOwner,
        uint256 sharesToRedeem
    ) external returns (uint256[] memory exitBalances, ERC20[] memory withdrawTokens);

    /// @dev Initiates a withdraw request
    function initiateWithdraw(
        address account,
        uint256 sharesHeld,
        uint256[] calldata exitBalances,
        bytes[] calldata withdrawData
    ) external returns (uint256[] memory requestIds);

    /// @dev Tokenizes a withdraw request during liquidation
    function tokenizeWithdrawRequest(
        address liquidateAccount,
        address liquidator,
        uint256 sharesToLiquidator
    ) external returns (bool didTokenize);

    /// @dev Checks if the account has pending withdrawals
    function hasPendingWithdrawals(address account) external view returns (bool);
}