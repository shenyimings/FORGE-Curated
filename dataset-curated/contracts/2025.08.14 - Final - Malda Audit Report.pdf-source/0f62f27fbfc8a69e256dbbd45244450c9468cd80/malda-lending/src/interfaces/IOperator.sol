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
import {ImTokenOperationTypes} from "./ImToken.sol";

interface IOperatorData {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market receives MALDA
        bool isMalded;
    }
}

interface IOperatorDefender {
    /**
     * @notice Checks if the account should be allowed to rebalance tokens
     * @param mToken The market to verify the transfer against
     */
    function beforeRebalancing(address mToken) external;

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param mToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of mTokens to transfer
     */
    function beforeMTokenTransfer(address mToken, address src, address dst, uint256 transferTokens) external;

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param mToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     */
    function beforeMTokenMint(address mToken, address minter) external;

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param mToken Asset being minted
     */
    function afterMTokenMint(address mToken) external view;

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param mToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of mTokens to exchange for the underlying asset in the market
     */
    function beforeMTokenRedeem(address mToken, address redeemer, uint256 redeemTokens) external;

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param mToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function beforeMTokenBorrow(address mToken, address borrower, uint256 borrowAmount) external;

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param mToken The market to verify the repay against
     * @param borrower The account which would borrowed the asset
     */
    function beforeMTokenRepay(address mToken, address borrower) external;

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param mTokenBorrowed Asset which was borrowed by the borrower
     * @param mTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function beforeMTokenLiquidate(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view;

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param mTokenCollateral Asset which was used as collateral and will be seized
     * @param mTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     */
    function beforeMTokenSeize(address mTokenCollateral, address mTokenBorrowed, address liquidator, address borrower)
        external;

    /**
     * @notice Checks if new used amount is within the limits of the outflow volume limit
     * @dev Sender must be a listed market
     * @param amount New amount
     */
    function checkOutflowVolumeLimit(uint256 amount) external;

    /**
     * @notice Checks whitelist status on withdrawOnExtension
     * @param user The user to check
     */
    function beforeWithdrawOnExtension(address user) external view;

    /**
     * @notice Checks whitelist status on borrowOnExtension
     * @param user The user to check
     */
    function beforeBorrowOnExtension(address user) external view;
}

interface IOperator {
    // ----------- VIEW ------------
    /**
     * @notice Returns true/false for user
     */
    function userWhitelisted(address _user) external view returns (bool);

    /**
     * @notice Should return true
     */
    function isOperator() external view returns (bool);

    /**
     * @notice Should return outflow limit 
     */
    function limitPerTimePeriod() external view returns (uint256); 

    /**
     * @notice Should return outflow volume 
     */
    function cumulativeOutflowVolume() external view returns (uint256); 

    /**
     * @notice Should return last reset time for outflow check
     */
    function lastOutflowResetTimestamp() external view returns (uint256); 

    /**
     * @notice Should return the outflow volume time window
     */
    function outflowResetTimeWindow() external view returns (uint256);

    /**
     * @notice Returns if operation is paused
     * @param mToken The mToken to check
     * @param _type the operation type
     */
    function isPaused(address mToken, ImTokenOperationTypes.OperationType _type) external view returns (bool);

    /**
     * @notice Roles manager
     */
    function rolesOperator() external view returns (IRoles);

    /**
     * @notice Oracle which gives the price of any given asset
     */
    function oracleOperator() external view returns (address);

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    function closeFactorMantissa() external view returns (uint256);

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    function liquidationIncentiveMantissa(address market) external view returns (uint256);

    /**
     * @notice Returns true/false
     */
    function isMarketListed(address market) external view returns (bool);

    /**
     * @notice Returns the assets an account has entered
     * @param _user The address of the account to pull assets for
     * @return mTokens A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address _user) external view returns (address[] memory mTokens);

    /**
     * @notice A list of all markets
     */
    function getAllMarkets() external view returns (address[] memory mTokens);

    /**
     * @notice Borrow caps enforced by borrowAllowed for each mToken address. Defaults to zero which corresponds to unlimited borrowing.
     */
    function borrowCaps(address _mToken) external view returns (uint256);

    /**
     * @notice Supply caps enforced by supplyAllowed for each mToken address. Defaults to zero which corresponds to unlimited supplying.
     */
    function supplyCaps(address _mToken) external view returns (uint256);

    /**
     * @notice Reward Distributor to markets supply and borrow (including protocol token)
     */
    function rewardDistributor() external view returns (address);

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param mToken The mToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, address mToken) external view returns (bool);

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return  account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) external view returns (uint256, uint256);

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param mTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return hypothetical account liquidity in excess of collateral requirements,
     *         hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256);

    /**
     * @notice Returns USD value for all markets
     */
    function getUSDValueForAllMarkets() external view returns (uint256);


    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in mTokenBorrowed.liquidate)
     * @param mTokenBorrowed The address of the borrowed mToken
     * @param mTokenCollateral The address of the collateral mToken
     * @param actualRepayAmount The amount of mTokenBorrowed underlying to convert into mTokenCollateral tokens
     * @return number of mTokenCollateral tokens to be seized in a liquidation
     */
    function liquidateCalculateSeizeTokens(address mTokenBorrowed, address mTokenCollateral, uint256 actualRepayAmount)
        external
        view
        returns (uint256);

    /**
     * @notice Returns true if the given mToken market has been deprecated
     * @dev All borrows in a deprecated mToken market can be immediately liquidated
     * @param mToken The market to check if deprecated
     */
    function isDeprecated(address mToken) external view returns (bool);

    // ----------- ACTIONS ------------
    /**
     * @notice Set pause for a specific operation
     * @param mToken The market token address
     * @param _type The pause operation type
     * @param state The pause operation status
     */
    function setPaused(address mToken, ImTokenOperationTypes.OperationType _type, bool state) external;

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param _mTokens The list of addresses of the mToken markets to be enabled
     */
    function enterMarkets(address[] calldata _mTokens) external;

    /**
     * @notice Add asset (msg.sender) to be included in account liquidity calculation
     * @param _account The account to add for
     */
    function enterMarketsWithSender(address _account) external;

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param _mToken The address of the asset to be removed
     */
    function exitMarket(address _mToken) external;

    /**
     * @notice Claim all the MALDA accrued by holder in all markets
     * @param holder The address to claim MALDA for
     */
    function claimMalda(address holder) external;

    /**
     * @notice Claim all the MALDA accrued by holder in the specified markets
     * @param holder The address to claim MALDA for
     * @param mTokens The list of markets to claim MALDA in
     */
    function claimMalda(address holder, address[] memory mTokens) external;

    /**
     * @notice Claim all MALDA accrued by the holders
     * @param holders The addresses to claim MALDA for
     * @param mTokens The list of markets to claim MALDA in
     * @param borrowers Whether or not to claim MALDA earned by borrowing
     * @param suppliers Whether or not to claim MALDA earned by supplying
     */
    function claimMalda(address[] memory holders, address[] memory mTokens, bool borrowers, bool suppliers) external;
}
