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
import {IOracleOperator} from "src/interfaces/IOracleOperator.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {ImToken, ImTokenOperationTypes} from "src/interfaces/ImToken.sol";
import {IOperatorData, IOperator, IOperatorDefender} from "src/interfaces/IOperator.sol";

// contracts
import {OperatorStorage} from "./OperatorStorage.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Operator is OperatorStorage, ImTokenOperationTypes, OwnableUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _rolesOperator, address _rewardDistributor, address _admin) public initializer {
        require(_rolesOperator != address(0), Operator_InvalidRolesOperator());
        require(_rewardDistributor != address(0), Operator_InvalidRewardDistributor());
        require(_admin != address(0), Operator_InvalidInput());
        __Ownable_init(_admin);
        rolesOperator = IRoles(_rolesOperator);
        rewardDistributor = _rewardDistributor;
        outflowResetTimeWindow = 1 hours;
        lastOutflowResetTimestamp = block.timestamp;
        limitPerTimePeriod = 0;
    }

    modifier onlyAllowedUser(address user) {
        if (whitelistEnabled) {
            require(userWhitelisted[user], Operator_UserNotWhitelisted());
        }
        _;
    }


    // ----------- OWNER ------------
    /**
     * @notice Sets user whitelist status
     * @param user The user address
     * @param state The new staate
     */
    function setWhitelistedUser(address user, bool state) external onlyOwner {
        userWhitelisted[user] = state;
        emit UserWhitelisted(user, state);
    }

    /**
     * @notice Enable user whitelist
     */
    function enableWhitelist() external onlyOwner {
        whitelistEnabled = true;
        emit WhitelistEnabled();
    }

    /**
     * @notice Disable user whitelist
     */
    function disableWhitelist() external onlyOwner {
        whitelistEnabled = false;
        emit WhitelistDisabled();
    }

    /**
     * @notice Sets a new Operator for the market
     * @dev Admin function to set a new operator
     */
    function setRolesOperator(address _roles) external onlyOwner {
        require(_roles != address(0), Operator_InvalidInput());

        emit NewRolesOperator(address(rolesOperator), _roles);

        rolesOperator = IRoles(_roles);
    }

    /**
     * @notice Sets a new price oracle
     * @dev Admin function to set a new price oracle
     */
    function setPriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), Operator_InvalidInput());
        emit NewPriceOracle(oracleOperator, newOracle);
        oracleOperator = newOracle;
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external onlyOwner {
        require(
            newCloseFactorMantissa >= CLOSE_FACTOR_MIN_MANTISSA && newCloseFactorMantissa <= CLOSE_FACTOR_MAX_MANTISSA,
            Operator_InvalidInput()
        );
        emit NewCloseFactor(closeFactorMantissa, newCloseFactorMantissa);
        closeFactorMantissa = newCloseFactorMantissa;
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param mToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     */
    function setCollateralFactor(address mToken, uint256 newCollateralFactorMantissa) external onlyOwner {
        // Verify market is listed
        IOperatorData.Market storage market = markets[address(mToken)];
        require(market.isListed, Operator_MarketNotListed());

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: COLLATERAL_FACTOR_MAX_MANTISSA});

        require(!lessThanExp(highLimit, newCollateralFactorExp), Operator_InvalidCollateralFactor());

        if (newCollateralFactorMantissa != 0 && IOracleOperator(oracleOperator).getUnderlyingPrice(mToken) == 0) {
            revert Operator_EmptyPrice();
        }

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(mToken, market.collateralFactorMantissa, newCollateralFactorMantissa);

        // Set market's collateral factor to new collateral factor, remember old value
        market.collateralFactorMantissa = newCollateralFactorMantissa;
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     */
    function setLiquidationIncentive(address market, uint256 newLiquidationIncentiveMantissa) external onlyOwner {
        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(market, liquidationIncentiveMantissa[market], newLiquidationIncentiveMantissa);

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa[market] = newLiquidationIncentiveMantissa;
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param mToken The address of the market (token) to list
     */
    function supportMarket(address mToken) external onlyOwner {
        require(!markets[address(mToken)].isListed, Operator_MarketAlreadyListed());
        require(ImToken(mToken).isMToken(), Operator_WrongMarket());

        // Note that isMalded is not in active use anymore
        IOperatorData.Market storage newMarket = markets[mToken];
        newMarket.isListed = true;
        newMarket.isMalded = false;
        newMarket.collateralFactorMantissa = 0;

        for (uint256 i = 0; i < allMarkets.length;) {
            require(allMarkets[i] != mToken, Operator_MarketAlreadyListed());

            unchecked {
                ++i;
            }
        }
        allMarkets.push(mToken);

        emit MarketListed(mToken);
    }   

    /**
     * @notice Sets outflow volume time window
     * @param newTimeWindow The new reset time window
     */  
    function setOutflowVolumeTimeWindow(uint256 newTimeWindow) external onlyOwner {
        emit OutflowTimeWindowUpdated(outflowResetTimeWindow, newTimeWindow);
        outflowResetTimeWindow = newTimeWindow;
    }

    /**
     * @notice Sets outflow volume limit
     * @dev when 0, it means there's no limit
     * @param amount The new limit
     */    
    function setOutflowTimeLimitInUSD(uint256 amount) external onlyOwner {
        emit OutflowLimitUpdated(msg.sender, limitPerTimePeriod, amount);
        limitPerTimePeriod = amount;
    }

    /**
     * @notice Resets outflow volume
     */  
    function resetOutflowVolume() external onlyOwner {
        cumulativeOutflowVolume = 0;
        emit OutflowVolumeReset();
    }

    /**
     * @notice Verifies outflow volule limit
     * @param amount The new limit
     */    
    function checkOutflowVolumeLimit(uint256 amount) external {
        require(ImToken(msg.sender).isMToken(), Operator_WrongMarket());
        require(markets[msg.sender].isListed, Operator_MarketNotListed());

        // skip this check in case limit is disabled ( = 0)
        if (limitPerTimePeriod > 0) {

            // check if we need to reset it
            if (block.timestamp > lastOutflowResetTimestamp + outflowResetTimeWindow) {
                cumulativeOutflowVolume = 0;
                lastOutflowResetTimestamp = block.timestamp;
            }

            // convert received amount to USD
            uint256 amountInUSD = _convertMarketAmountToUSDValue(amount, msg.sender);

            // check new cumulative limits
            if (cumulativeOutflowVolume + amountInUSD > limitPerTimePeriod) revert Operator_OutflowVolumeReached();
            cumulativeOutflowVolume += amountInUSD;
        }
    }

    /**
     * @notice Set the given borrow caps for the given mToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @param mTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    function setMarketBorrowCaps(address[] calldata mTokens, uint256[] calldata newBorrowCaps) external {
        require(
            msg.sender == owner() || rolesOperator.isAllowedFor(msg.sender, rolesOperator.GUARDIAN_BORROW_CAP()),
            Operator_OnlyAdminOrRole()
        );

        uint256 numMarkets = mTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, Operator_InvalidInput());

        for (uint256 i; i < numMarkets;) {
            borrowCaps[mTokens[i]] = newBorrowCaps[i];
            emit NewBorrowCap(mTokens[i], newBorrowCaps[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set the given supply caps for the given mToken markets. Supplying that brings total supply to or above supply cap will revert.
     * @param mTokens The addresses of the markets (tokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set. A value of 0 corresponds to unlimited supplying.
     */
    function setMarketSupplyCaps(address[] calldata mTokens, uint256[] calldata newSupplyCaps) external {
        require(
            msg.sender == owner() || rolesOperator.isAllowedFor(msg.sender, rolesOperator.GUARDIAN_SUPPLY_CAP()),
            Operator_OnlyAdminOrRole()
        );

        uint256 numMarkets = mTokens.length;
        uint256 numSupplyCaps = newSupplyCaps.length;
        require(numMarkets != 0 && numMarkets == numSupplyCaps, Operator_InvalidInput());

        for (uint256 i; i < numMarkets;) {
            supplyCaps[mTokens[i]] = newSupplyCaps[i];
            emit NewSupplyCap(mTokens[i], newSupplyCaps[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IOperator
     */
    function setPaused(address mToken, ImTokenOperationTypes.OperationType _type, bool state) external {
        if (state) {
            require(
                msg.sender == owner() || rolesOperator.isAllowedFor(msg.sender, rolesOperator.GUARDIAN_PAUSE()),
                Operator_OnlyAdminOrRole()
            );
        } else {
            // only admin can unpause
            require(msg.sender == owner(), Operator_OnlyAdmin());
        }

        _paused[mToken][_type] = state;
        emit ActionPaused(mToken, _type, state);
    }

    /**
     * @notice Admin function to change the Reward Distributor
     * @param newRewardDistributor The address of the new Reward Distributor
     */
    function setRewardDistributor(address newRewardDistributor) external onlyOwner {
        // Emit NewRewardDistributor(OldRewardDistributor, NewRewardDistributor)
        emit NewRewardDistributor(rewardDistributor, newRewardDistributor);

        // Store rewardDistributor with value newRewardDistributor
        rewardDistributor = newRewardDistributor;
    }

    // ----------- VIEW ------------
    /**
     * @inheritdoc IOperator
     */
    function isOperator() external pure override returns (bool) {
        return true;
    }

    /**
     * @inheritdoc IOperator
     */
    function isPaused(address mToken, ImTokenOperationTypes.OperationType _type)
        external
        view
        override
        returns (bool)
    {
        return _paused[mToken][_type];
    }

    /**
     * @inheritdoc IOperator
     */
    function getAssetsIn(address _user) external view override returns (address[] memory mTokens) {
        return accountAssets[_user];
    }

    /**
     * @inheritdoc IOperator
     */
    function checkMembership(address account, address mToken) external view returns (bool) {
        return markets[mToken].accountMembership[account];
    }

    /**
     * @inheritdoc IOperator
     */
    function getAllMarkets() external view returns (address[] memory mTokens) {
        return allMarkets;
    }

    /**
     * @inheritdoc IOperator
     */
    function isDeprecated(address mToken) external view override returns (bool) {
        return _isDeprecated(mToken);
    }

    /**
     * @inheritdoc IOperator
     */
    function isMarketListed(address mToken) external view override returns (bool) {
        return markets[mToken].isListed;
    }

    /**
     * @inheritdoc IOperator
     */
    function getAccountLiquidity(address account) public view returns (uint256, uint256) {
        return _getHypotheticalAccountLiquidity(account, address(0), 0, 0);
    }

    /**
     * @inheritdoc IOperator
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256) {
        return _getHypotheticalAccountLiquidity(account, mTokenModify, redeemTokens, borrowAmount);
    }

    /**
     * @inheritdoc IOperator
     */
    function liquidateCalculateSeizeTokens(address mTokenBorrowed, address mTokenCollateral, uint256 actualRepayAmount)
        external
        view
        returns (uint256)
    {
        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedMantissa = IOracleOperator(oracleOperator).getUnderlyingPrice(mTokenBorrowed);
        uint256 priceCollateralMantissa = IOracleOperator(oracleOperator).getUnderlyingPrice(mTokenCollateral);
        require(priceBorrowedMantissa > 0 && priceCollateralMantissa > 0, Operator_PriceFetchFailed());

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateMantissa = ImToken(mTokenCollateral).exchangeRateStored();

        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;
        numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa[mTokenCollateral]}), Exp({mantissa: priceBorrowedMantissa}));
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        ratio = div_(numerator, denominator);

        return mul_ScalarTruncate(ratio, actualRepayAmount);
    }

    // ----------- PUBLIC ------------
    /**
     * @inheritdoc IOperator
     */
    function enterMarkets(address[] calldata _mTokens) external override onlyAllowedUser(msg.sender) {
        uint256 len = _mTokens.length;
        for (uint256 i = 0; i < len;) {
            address __mToken = _mTokens[i];
            _activateMarket(__mToken, msg.sender);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IOperator
     */
    function enterMarketsWithSender(address _account) external override onlyAllowedUser(_account) {
        //sender needs to be a listed market
        IOperatorData.Market storage market = markets[msg.sender];
        require(market.isListed, Operator_MarketNotListed());
        _activateMarket(msg.sender, _account);
    }

    /**
     * @inheritdoc IOperator
     */
    function exitMarket(address _mToken) external override {
        IOperatorData.Market storage marketToExit = markets[_mToken];
        /* Return  if the sender is not already 'in' the market */
        if (!marketToExit.accountMembership[msg.sender]) return;

        /* Get sender tokensHeld and amountOwed underlying from the mToken */
        (uint256 tokensHeld, uint256 amountOwed,) = ImToken(_mToken).getAccountSnapshot(msg.sender);

        require(amountOwed == 0, Operator_Deactivate_MarketBalanceOwed());

        /* Redeem check */
        _beforeRedeem(_mToken, msg.sender, tokensHeld);

        /* Set mToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete mToken from the account's list of assets */
        // load into memory for faster iteration
        address[] memory userAssetList = accountAssets[msg.sender];
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i; i < len;) {
            if (userAssetList[i] == _mToken) {
                assetIndex = i;
                break;
            }

            unchecked {
                ++i;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        require(assetIndex < len, Operator_AssetNotFound());

        // copy last item in list to location of item to be removed, reduce length by 1
        address[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(_mToken, msg.sender);
    }

    /**
     * @notice Claim all the MALDA accrued by holder in all markets
     * @param holder The address to claim MALDA for
     */
    function claimMalda(address holder) external override {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        return _claim(holders, allMarkets, true, true);
    }

    /**
     * @notice Claim all the MALDA accrued by holder in the specified markets
     * @param holder The address to claim MALDA for
     * @param mTokens The list of markets to claim MALDA in
     */
    function claimMalda(address holder, address[] memory mTokens) external override {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        _claim(holders, mTokens, true, true);
    }

    /**
     * @notice Claim all MALDA accrued by the holders
     * @param holders The addresses to claim MALDA for
     * @param mTokens The list of markets to claim MALDA in
     * @param borrowers Whether or not to claim MALDA earned by borrowing
     * @param suppliers Whether or not to claim MALDA earned by supplying
     */
    function claimMalda(address[] memory holders, address[] memory mTokens, bool borrowers, bool suppliers)
        external
        override
    {
        _claim(holders, mTokens, borrowers, suppliers);
    }
    
    /**
     * @notice Returns USD value for all markets
    */
    function getUSDValueForAllMarkets() external view returns (uint256) {
        uint256 sum;
        for (uint256 i; i < allMarkets.length;) {
            ImToken _market = ImToken(allMarkets[i]);
            if (_isDeprecated(address(_market))) { continue;}
            uint256 totalMarketVolume = _market.totalUnderlying();
            sum += _convertMarketAmountToUSDValue(totalMarketVolume, address(_market));
            unchecked {  ++i; }
        }
        return sum;
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeWithdrawOnExtension(address user) external view onlyAllowedUser(user){}

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeBorrowOnExtension(address user) external view onlyAllowedUser(user){}

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeRebalancing(address mToken) external view override {
        require(!_paused[mToken][OperationType.Rebalancing], Operator_Paused());
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeMTokenTransfer(address mToken, address src, address dst, uint256 transferTokens) external override {
        require(!_paused[mToken][OperationType.Transfer], Operator_Paused());

        /* Get sender tokensHeld and amountOwed underlying from the mToken */
        _beforeRedeem(mToken, src, transferTokens);

        // Keep the flywheel moving
        _updateMaldaSupplyIndex(mToken);
        _distributeSupplierMalda(mToken, src);
        _distributeSupplierMalda(mToken, dst);
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeMTokenMint(address mToken, address minter) external override onlyAllowedUser(minter) {
        require(!_paused[mToken][OperationType.Mint], Operator_Paused());
        require(markets[mToken].isListed, Operator_MarketNotListed());
        // Keep the flywheel moving
        _updateMaldaSupplyIndex(mToken);
        _distributeSupplierMalda(mToken, minter);
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function afterMTokenMint(address mToken) external view override {
        uint256 supplyCap = supplyCaps[mToken];
        // Supply cap of 0 corresponds to unlimited borrowing
        if (supplyCap != 0) {
            uint256 totalSupply = ImToken(mToken).totalSupply();
            Exp memory exchangeRate = Exp({mantissa: ImToken(mToken).exchangeRateStored()});
            uint256 totalAmount = mul_ScalarTruncate(exchangeRate, totalSupply);
            require(totalAmount <= supplyCap, Operator_MarketSupplyReached());
        }
    }
    /**
     * @inheritdoc IOperatorDefender
     */

    function beforeMTokenRedeem(address mToken, address redeemer, uint256 redeemTokens) external override onlyAllowedUser(redeemer) {
        _beforeRedeem(mToken, redeemer, redeemTokens);

        // Keep the flywheel moving
        _updateMaldaSupplyIndex(mToken);
        _distributeSupplierMalda(mToken, redeemer);
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeMTokenBorrow(address mToken, address borrower, uint256 borrowAmount) external override onlyAllowedUser(borrower) {
        require(!_paused[mToken][OperationType.Borrow], Operator_Paused());
        require(markets[mToken].isListed, Operator_MarketNotListed());

        if (!markets[mToken].accountMembership[borrower]) {
            require(msg.sender == mToken, Operator_SenderMustBeToken());

            _activateMarket(mToken, borrower);
            require(markets[mToken].accountMembership[borrower], Operator_WrongMarket());
        }

        require(IOracleOperator(oracleOperator).getUnderlyingPrice(mToken) != 0, Operator_EmptyPrice());

        uint256 borrowCap = borrowCaps[mToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint256 totalBorrows = ImToken(mToken).totalBorrows();
            uint256 nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, Operator_MarketBorrowCapReached());
        }

        // liquidity check
        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(borrower, mToken, 0, borrowAmount);
        require(shortfall == 0, Operator_InsufficientLiquidity());

        // Keep the flywheel moving
        _updateMaldaBorrowIndex(mToken);
        _distributeBorrowerMalda(mToken, borrower);
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeMTokenRepay(address mToken, address borrower) external onlyAllowedUser(borrower) {
        require(!_paused[mToken][OperationType.Repay], Operator_Paused());
        require(markets[mToken].isListed, Operator_MarketNotListed());

        // Keep the flywheel moving
        _updateMaldaBorrowIndex(mToken);
        _distributeBorrowerMalda(mToken, borrower);
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeMTokenLiquidate(
        address mTokenBorrowed,
        address mTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view override onlyAllowedUser(borrower) {
        require(!_paused[mTokenBorrowed][OperationType.Liquidate], Operator_Paused());
        require(markets[mTokenBorrowed].isListed, Operator_MarketNotListed());
        require(markets[mTokenCollateral].isListed, Operator_MarketNotListed());

        uint256 borrowBalance = ImToken(mTokenBorrowed).borrowBalanceStored(borrower);

        if (_isDeprecated(mTokenBorrowed)) {
            require(borrowBalance >= repayAmount, Operator_RepayAmountNotValid());
        } else {
            (, uint256 shortfall) = _getHypotheticalAccountLiquidity(borrower, address(0), 0, 0);
            require(shortfall > 0, Operator_InsufficientLiquidity());

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint256 maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
            require(repayAmount <= maxClose, Operator_RepayingTooMuch());
        }
    }

    /**
     * @inheritdoc IOperatorDefender
     */
    function beforeMTokenSeize(address mTokenCollateral, address mTokenBorrowed, address liquidator, address borrower)
        external
        override
    {
        require(
            !_paused[mTokenCollateral][OperationType.Seize] && !_paused[mTokenBorrowed][OperationType.Seize],
            Operator_Paused()
        );
        require(markets[mTokenBorrowed].isListed, Operator_MarketNotListed());
        require(markets[mTokenCollateral].isListed, Operator_MarketNotListed());
        require(ImToken(mTokenCollateral).operator() == ImToken(mTokenBorrowed).operator(), Operator_Mismatch());

        // Keep the flywheel moving
        _updateMaldaSupplyIndex(mTokenCollateral);
        _distributeSupplierMalda(mTokenCollateral, borrower);
        _distributeSupplierMalda(mTokenCollateral, liquidator);
    }

    // ----------- PRIVATE ------------
    function _convertMarketAmountToUSDValue(uint256 amount, address mToken) internal view returns (uint256) {
        uint256 oraclePriceMantissa = IOracleOperator(oracleOperator).getUnderlyingPrice(mToken);
        require(oraclePriceMantissa != 0, Operator_OracleUnderlyingFetchError());

        Exp memory oraclePrice = Exp({mantissa: oraclePriceMantissa});
        return mul_(amount, oraclePrice) / 1e10;
    }

    

    function _activateMarket(address _mToken, address borrower) private {
        IOperatorData.Market storage marketToJoin = markets[_mToken];
        require(marketToJoin.isListed, Operator_MarketNotListed());

        if (!marketToJoin.accountMembership[borrower]) {
            marketToJoin.accountMembership[borrower] = true;
            accountAssets[borrower].push(_mToken);
            emit MarketEntered(_mToken, borrower);
        }
    }

    function _beforeRedeem(address mToken, address redeemer, uint256 redeemTokens) private view {
        require(!_paused[mToken][OperationType.Redeem], Operator_Paused());
        require(markets[mToken].isListed, Operator_MarketNotListed());

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[mToken].accountMembership[redeemer]) return;

        // liquidity check
        (, uint256 shortfall) = _getHypotheticalAccountLiquidity(redeemer, mToken, redeemTokens, 0);
        require(shortfall == 0, Operator_InsufficientLiquidity());
    }

    function _getHypotheticalAccountLiquidity(
        address account,
        address mTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) private view returns (uint256, uint256) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results

        uint256 len = accountAssets[account].length;
        for (uint256 i; i < len;) {
            address _asset = accountAssets[account][i];

            // Read the balances and exchange rate from the mToken
            (vars.mTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) =
                ImToken(_asset).getAccountSnapshot(account);

            vars.collateralFactor = Exp({mantissa: markets[_asset].collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = IOracleOperator(oracleOperator).getUnderlyingPrice(_asset);
            require(vars.oraclePriceMantissa != 0, Operator_OracleUnderlyingFetchError());

            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * mTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.mTokenBalance, vars.sumCollateral);
            

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects =
                mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with mTokenModify
            if (_asset == mTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects =
                    mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects =
                    mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }

            unchecked {
                ++i;
            }
        }

        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Notify reward distributor for supply index update
     * @param mToken The market whose supply index to update
     */
    function _updateMaldaSupplyIndex(address mToken) private {
        IRewardDistributor(rewardDistributor).notifySupplyIndex(mToken);
    }

    /**
     * @notice Notify reward distributor for borrow index update
     * @param mToken The market whose borrow index to update
     */
    function _updateMaldaBorrowIndex(address mToken) private {
        IRewardDistributor(rewardDistributor).notifyBorrowIndex(mToken);
    }

    /**
     * @notice Notify reward distributor for supplier update
     * @param mToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute MALDA to
     */
    function _distributeSupplierMalda(address mToken, address supplier) private {
        IRewardDistributor(rewardDistributor).notifySupplier(mToken, supplier);
    }

    /**
     * @notice Notify reward distributor for borrower update
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param mToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute MALDA to
     */
    function _distributeBorrowerMalda(address mToken, address borrower) private {
        IRewardDistributor(rewardDistributor).notifyBorrower(mToken, borrower);
    }

    function _claim(address[] memory holders, address[] memory mTokens, bool borrowers, bool suppliers) private {
        uint256 len = mTokens.length;
        for (uint256 i; i < len;) {
            address mToken = mTokens[i];
            require(markets[mToken].isListed, Operator_MarketNotListed());
            if (borrowers) {
                _updateMaldaBorrowIndex(address(mToken));
                for (uint256 j = 0; j < holders.length;) {
                    _distributeBorrowerMalda(address(mToken), holders[j]);

                    unchecked {
                        ++j;
                    }
                }
            }
            if (suppliers) {
                _updateMaldaSupplyIndex(address(mToken));
                for (uint256 j = 0; j < holders.length;) {
                    _distributeSupplierMalda(address(mToken), holders[j]);

                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        IRewardDistributor(rewardDistributor).claim(holders);
    }

    function _isDeprecated(address mToken) private view returns (bool) {
        return markets[mToken].collateralFactorMantissa == 0 && _paused[mToken][OperationType.Borrow]
            && ImToken(mToken).reserveFactorMantissa() == 1e18;
    }
}
