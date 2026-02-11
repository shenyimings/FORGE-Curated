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

// interfaces
import {IRoles} from "src/interfaces/IRoles.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {IOperatorData, IOperator, IOperatorDefender} from "src/interfaces/IOperator.sol";

// contracts
import {ExponentialNoError} from "src/utils/ExponentialNoError.sol";

abstract contract OperatorStorage is IOperator, IOperatorDefender, ExponentialNoError {
    // ----------- STORAGE ------------
    /**
     * @inheritdoc IOperator
     */
    IRoles public rolesOperator;

    /**
     * @inheritdoc IOperator
     */
    address public oracleOperator;

    /**
     * @inheritdoc IOperator
     */
    uint256 public closeFactorMantissa;

    /**
     * @inheritdoc IOperator
     */
    mapping(address => uint256) public liquidationIncentiveMantissa;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => address[]) public accountAssets;

    /**
     * @notice Official mapping of mTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => IOperatorData.Market) public markets;

    /**
     * @notice A list of all markets
     */
    address[] public allMarkets;

    /**
     * @inheritdoc IOperator
     */
    mapping(address => uint256) public borrowCaps;

    /**
     * @inheritdoc IOperator
     */
    mapping(address => uint256) public supplyCaps;

    /**
     * @inheritdoc IOperator
     */
    address public rewardDistributor;

    /**
     * @inheritdoc IOperator
     */
    uint256 public limitPerTimePeriod; 

    /**
     * @inheritdoc IOperator
     */
    uint256 public cumulativeOutflowVolume; 

    /**
     * @inheritdoc IOperator
     */
    uint256 public lastOutflowResetTimestamp; 
    
    // Outflow time window
    /**
     * @inheritdoc IOperator
     */
    uint256 public outflowResetTimeWindow;

    /**
     * @inheritdoc IOperator
     */
    mapping(address => bool) public userWhitelisted;

    bool public whitelistEnabled;

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `mTokenBalance` is the number of mTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;
        uint256 mTokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    mapping(address => mapping(ImTokenOperationTypes.OperationType => bool)) internal _paused;

    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant CLOSE_FACTOR_MIN_MANTISSA = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint256 internal constant CLOSE_FACTOR_MAX_MANTISSA = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint256 internal constant COLLATERAL_FACTOR_MAX_MANTISSA = 0.9e18; // 0.95


    // ----------- ERRORS ------------
    error Operator_Paused();
    error Operator_Mismatch();
    error Operator_OnlyAdmin();
    error Operator_EmptyPrice();
    error Operator_WrongMarket();
    error Operator_InvalidInput();
    error Operator_AssetNotFound();
    error Operator_RepayingTooMuch();
    error Operator_OnlyAdminOrRole();
    error Operator_MarketNotListed();
    error Operator_PriceFetchFailed();
    error Operator_SenderMustBeToken();
    error Operator_UserNotWhitelisted();
    error Operator_MarketSupplyReached();
    error Operator_RepayAmountNotValid();
    error Operator_MarketAlreadyListed();
    error Operator_OutflowVolumeReached();
    error Operator_InvalidRolesOperator();
    error Operator_InsufficientLiquidity();
    error Operator_MarketBorrowCapReached();
    error Operator_InvalidCollateralFactor();
    error Operator_InvalidRewardDistributor();
    error Operator_OracleUnderlyingFetchError();
    error Operator_Deactivate_MarketBalanceOwed();

    // ----------- EVENTS ------------
    /**
     * @notice Emitted when user whitelist status is changed
     */
    event UserWhitelisted(address indexed user, bool state);
    event WhitelistEnabled();
    event WhitelistDisabled();

    /**
     * @notice Emitted when pause status is changed
     */
    event ActionPaused(address indexed mToken, ImTokenOperationTypes.OperationType _type, bool state);

    /// @notice Emitted when reward distributor is changed
    event NewRewardDistributor(address indexed oldRewardDistributor, address indexed newRewardDistributor);
    /**
     * @notice Emitted when borrow cap for a mToken is changed
     */
    event NewBorrowCap(address indexed mToken, uint256 newBorrowCap);

    /**
     * @notice Emitted when supply cap for a mToken is changed
     */
    event NewSupplyCap(address indexed mToken, uint256 newBorrowCap);

    /**
     * @notice Emitted when an admin supports a market
     */
    event MarketListed(address mToken);
    /**
     * @notice Emitted when an account enters a market
     */
    event MarketEntered(address indexed mToken, address indexed account);
    /**
     * @notice Emitted when an account exits a market
     */
    event MarketExited(address indexed mToken, address indexed account);
    /**
     * @notice Emitted Emitted when close factor is changed by admin
     */
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);
    /**
     * @notice Emitted when a collateral factor is changed by admin
     */
    event NewCollateralFactor(
        address indexed mToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa
    );
    /**
     * @notice Emitted when liquidation incentive is changed by admin
     */
    event NewLiquidationIncentive(address market, uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa);
    /**
     * @notice Emitted when price oracle is changed
     */
    event NewPriceOracle(address indexed oldPriceOracle, address indexed newPriceOracle);

    /**
     * @notice Event emitted when rolesOperator is changed
     */
    event NewRolesOperator(address indexed oldRoles, address indexed newRoles);

    /**
     * @notice Event emitted when outflow limit is updated
     */
    event OutflowLimitUpdated(address indexed sender, uint256 oldLimit, uint256 newLimit);
     
    /**
     * @notice Event emitted when outflow reset time window is updated
     */
    event OutflowTimeWindowUpdated(uint256 oldWindow, uint256 newWindow);

    /**
     * @notice Event emitted when outflow volume has been reset
     */
    event OutflowVolumeReset();

}
