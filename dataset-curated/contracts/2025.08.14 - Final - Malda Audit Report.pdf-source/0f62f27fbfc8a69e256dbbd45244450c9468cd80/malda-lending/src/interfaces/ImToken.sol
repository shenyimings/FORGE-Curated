// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                          
*/

import {IRoles} from "./IRoles.sol";

interface ImTokenOperationTypes {
    enum OperationType {
        AmountIn,
        AmountInHere,
        AmountOut,
        AmountOutHere,
        Seize,
        Transfer,
        Mint,
        Borrow,
        Repay,
        Redeem,
        Liquidate,
        Rebalancing
    }
}

interface ImTokenDelegator {
    /**
     * @notice Non-standard token able to delegate
     */
    function delegate(address delegatee) external;
}

interface ImTokenMinimal {
    /**
     * @notice EIP-20 token name for this token
     */
    function name() external view returns (string memory);

    /**
     * @notice EIP-20 token symbol for this token
     */
    function symbol() external view returns (string memory);

    /**
     * @notice EIP-20 token decimals for this token
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the amount of underlying tokens
     */
    function totalUnderlying() external view returns (uint256);

    /**
     * @notice Returns the value of tokens owned by `account`.
     * @param account The account to check for
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Returns true
     */
    function isMToken() external view returns (bool);

    /**
     * @dev Returns the underlying address
     */
    function underlying() external view returns (address);
}

interface ImToken is ImTokenMinimal {
    // ----------- STORAGE ------------
    /**
     * @notice Roles manager
     */
    function rolesOperator() external view returns (IRoles);

    /**
     * @notice Administrator for this contract
     */
    function admin() external view returns (address payable);

    /**
     * @notice Pending administrator for this contract
     */
    function pendingAdmin() external view returns (address payable);

    /**
     * @notice Contract which oversees inter-mToken operations
     */
    function operator() external view returns (address);

    /**
     * @notice Model which tells what the current interest rate should be
     */
    function interestRateModel() external view returns (address);

    /**
     * @notice Fraction of interest currently set aside for reserves
     */
    function reserveFactorMantissa() external view returns (uint256);

    /**
     * @notice Block timestamp that interest was last accrued at
     */
    function accrualBlockTimestamp() external view returns (uint256);

    /**
     * @notice Accumulator of the total earned interest rate since the opening of the market
     */
    function borrowIndex() external view returns (uint256);

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    function totalBorrows() external view returns (uint256);

    /**
     * @notice Total amount of reserves of the underlying held in this market
     */
    function totalReserves() external view returns (uint256);

    /**
     * @notice Returns true/false for same chain flow state disable status
     */
    function sameChainFlowStateDisabled() external view returns (bool);

    // ----------- ACTIONS ------------
    /**
     * @notice Transfers `amount` tokens to the `dst` address
     * @param dst The address of the recipient
     * @param amount The number of tokens to transfer
     * @return Whether the transfer was successful or not
     */
    function transfer(address dst, uint256 amount) external returns (bool);

    /**
     * @notice Transfers `amount` tokens from the `src` address to the `dst` address
     * @param src The address from which tokens are transferred
     * @param dst The address to which tokens are transferred
     * @param amount The number of tokens to transfer
     * @return Whether the transfer was successful or not
     */
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);

    /**
     * @notice Approves `spender` to spend `amount` tokens on behalf of the caller
     * @param spender The address authorized to spend tokens
     * @param amount The number of tokens to approve
     * @return Whether the approval was successful or not
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Returns the current allowance the `spender` has from the `owner`
     * @param owner The address of the token holder
     * @param spender The address authorized to spend the tokens
     * @return The current remaining number of tokens `spender` can spend
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @notice Returns the balance of tokens held by `owner`
     * @param owner The address to query the balance for
     * @return The balance of tokens owned by `owner`
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @notice Returns the underlying asset balance of the `owner`
     * @param owner The address to query the balance of underlying assets for
     * @return The balance of underlying assets owned by `owner`
     */
    function balanceOfUnderlying(address owner) external returns (uint256);

    /**
     * @notice Returns the snapshot of account details for the given `account`
     * @param account The address to query the account snapshot for
     * @return (token balance, borrow balance, exchange rate)
     */
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256);

    /**
     * @notice Returns the current borrow rate per block
     * @return The current borrow rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() external view returns (uint256);

    /**
     * @notice Returns the current supply rate per block
     * @return The current supply rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() external view returns (uint256);

    /**
     * @notice Returns the total amount of borrows, accounting for interest
     * @return The total amount of borrows
     */
    function totalBorrowsCurrent() external returns (uint256);

    /**
     * @notice Returns the current borrow balance for `account`, accounting for interest
     * @param account The address to query the borrow balance for
     * @return The current borrow balance
     */
    function borrowBalanceCurrent(address account) external returns (uint256);

    /**
     * @notice Returns the stored borrow balance for `account`, without accruing interest
     * @param account The address to query the stored borrow balance for
     * @return The stored borrow balance
     */
    function borrowBalanceStored(address account) external view returns (uint256);

    /**
     * @notice Returns the current exchange rate, with interest accrued
     * @return The current exchange rate
     */
    function exchangeRateCurrent() external returns (uint256);

    /**
     * @notice Returns the stored exchange rate, without accruing interest
     * @return The stored exchange rate
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Returns the total amount of available cash in the contract
     * @return The total amount of cash
     */
    function getCash() external view returns (uint256);

    /**
     * @notice Accrues interest on the contract's outstanding loans
     */
    function accrueInterest() external;

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another mToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed mToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of mTokens to seize
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens) external;

    /**
     * @notice Accrues interest and reduces reserves by transferring to admin
     * @param reduceAmount Amount of reduction to reserves
     */
    function reduceReserves(uint256 reduceAmount) external;
}
