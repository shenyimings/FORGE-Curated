// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";
import { Errors } from "src/libraries/Errors.sol";
import { MathUtils } from "src/libraries/MathUtils.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { BasketManagerStorage, RebalanceStatus, Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

/// @title BasketManagerUtils
/// @notice Library containing utility functions for managing storage related to baskets, including creating new
/// baskets, proposing and executing rebalances, and settling internal and external token trades.
library BasketManagerUtils {
    using SafeERC20 for IERC20;

    /// STRUCTS ///

    /// @notice Struct containing data for an internal trade.
    struct InternalTradeInfo {
        // Index of the basket that is selling.
        uint256 fromBasketIndex;
        // Index of the basket that is buying.
        uint256 toBasketIndex;
        // Index of the token to sell.
        uint256 sellTokenAssetIndex;
        // Index of the token to buy.
        uint256 buyTokenAssetIndex;
        // Index of the buy token in the buying basket.
        uint256 toBasketBuyTokenIndex;
        // Index of the sell token in the buying basket.
        uint256 toBasketSellTokenIndex;
        // Amount of the buy token that is traded.
        uint256 netBuyAmount;
        // Amount of the sell token that is traded.
        uint256 netSellAmount;
        // Fee charged on the buy token on the trade.
        uint256 feeOnBuy;
        // Fee charged on the sell token on the trade.
        uint256 feeOnSell;
    }

    /// @notice Struct containing data for an external trade.
    struct ExternalTradeInfo {
        // Price of the sell token.
        uint256 sellTokenPrice;
        // Price of the buy token.
        uint256 buyTokenPrice;
        // Value of the sell token.
        uint256 sellValue;
        // Minimum amount of the buy token that the trade results in.
        uint256 internalMinAmount;
        // Difference between the internalMinAmount and the minAmount.
        uint256 diff;
    }

    /// @notice Struct containing data for basket ownership of an external trade.
    struct BasketOwnershipInfo {
        // Index of the basket.
        uint256 basketIndex;
        // Index of the buy token asset.
        uint256 buyTokenAssetIndex;
        // Index of the sell token asset.
        uint256 sellTokenAssetIndex;
    }

    /// CONSTANTS ///
    /// @notice ISO 4217 numeric code for USD, used as a constant address representation
    address private constant _USD_ISO_4217_CODE = address(840);
    /// @notice Maximum number of basket tokens allowed to be created.
    uint256 private constant _MAX_NUM_OF_BASKET_TOKENS = 256;
    /// @notice Maximum slippage multiplier for token swaps, expressed in 1e18.
    uint256 private constant _MAX_SLIPPAGE = 0.05e18; // 5%
    /// @notice Maximum deviation multiplier to determine if a set of balances has reached the desired target weights.
    uint256 private constant _MAX_WEIGHT_DEVIATION = 0.05e18; // 5%
    /// @notice Precision used for weight calculations and slippage calculations.
    uint256 private constant _WEIGHT_PRECISION = 1e18;
    /// @notice Maximum number of retries for a rebalance.
    uint8 private constant _MAX_RETRIES = 3;
    /// @notice Minimum time between rebalances in seconds.
    uint40 private constant _REBALANCE_COOLDOWN_SEC = 1 hours;

    /// EVENTS ///
    /// @notice Emitted when an internal trade is settled.
    /// @param internalTrade Internal trade that was settled.
    /// @param buyAmount Amount of the the from token that is traded.
    event InternalTradeSettled(InternalTrade internalTrade, uint256 buyAmount);
    /// @notice Emitted when swap fees are charged on an internal trade.
    /// @param asset Asset that the swap fee was charged in.
    /// @param amount Amount of the asset that was charged.
    event SwapFeeCharged(address indexed asset, uint256 amount);
    /// @notice Emitted when a rebalance is proposed for a set of baskets
    /// @param epoch Unique identifier for the rebalance, incremented each time a rebalance is proposed
    /// @param baskets Array of basket addresses to rebalance
    /// @param proposedTargetWeights Array of target weights for each basket
    /// @param basketHash Hash of the basket addresses and target weights for the rebalance
    event RebalanceProposed(
        uint40 indexed epoch, address[] baskets, uint64[][] proposedTargetWeights, bytes32 basketHash
    );
    /// @notice Emitted when a rebalance is completed.
    event RebalanceCompleted(uint40 indexed epoch);

    /// ERRORS ///
    /// @dev Reverts when the total supply of a basket token is zero.
    error ZeroTotalSupply();
    /// @dev Reverts when the amount of burned shares is zero.
    error ZeroBurnedShares();
    /// @dev Reverts when trying to burn more shares than the total supply.
    error CannotBurnMoreSharesThanTotalSupply();
    /// @dev Reverts when the requested basket token is not found.
    error BasketTokenNotFound();
    /// @dev Reverts when the requested asset is not found in the basket.
    error AssetNotFoundInBasket();
    /// @dev Reverts when trying to create a basket token that already exists.
    error BasketTokenAlreadyExists();
    /// @dev Reverts when the maximum number of basket tokens has been reached.
    error BasketTokenMaxExceeded();
    /// @dev Reverts when the requested element index is not found.
    error ElementIndexNotFound();
    /// @dev Reverts when the strategy registry does not support the given strategy.
    error StrategyRegistryDoesNotSupportStrategy();
    /// @dev Reverts when the baskets or target weights do not match the proposed rebalance.
    error BasketsMismatch();
    /// @dev Reverts when the base asset does not match the given asset.
    error BaseAssetMismatch();
    /// @dev Reverts when the asset is not found in the asset registry.
    error AssetListEmpty();
    /// @dev Reverts when a rebalance is in progress and the caller must wait for it to complete.
    error MustWaitForRebalanceToComplete();
    /// @dev Reverts when there is no rebalance in progress.
    error NoRebalanceInProgress();
    /// @dev Reverts when it is too early to complete the rebalance.
    error TooEarlyToCompleteRebalance();
    /// @dev Reverts when it is too early to propose a rebalance.
    error TooEarlyToProposeRebalance();
    /// @dev Reverts when a rebalance is not required.
    error RebalanceNotRequired();
    /// @dev Reverts when the external trade slippage exceeds the allowed limit.
    error ExternalTradeSlippage();
    /// @dev Reverts when the target weights are not met.
    error TargetWeightsNotMet();
    /// @dev Reverts when the minimum or maximum amount is not reached for an internal trade.
    error InternalTradeMinMaxAmountNotReached();
    /// @dev Reverts when the trade token amount is incorrect.
    error IncorrectTradeTokenAmount();
    /// @dev Reverts when given external trades do not match.
    error ExternalTradeMismatch();
    /// @dev Reverts when the delegatecall to the tokenswap adapter fails.
    error CompleteTokenSwapFailed();
    /// @dev Reverts when an asset included in a bit flag is not enabled in the asset registry.
    error AssetNotEnabled();

    /// @notice Creates a new basket token with the given parameters.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketName Name of the basket.
    /// @param symbol Symbol of the basket.
    /// @param bitFlag Asset selection bitFlag for the basket.
    /// @param strategy Address of the strategy contract for the basket.
    /// @return basket Address of the newly created basket token.
    function createNewBasket(
        BasketManagerStorage storage self,
        string calldata basketName,
        string calldata symbol,
        address baseAsset,
        uint256 bitFlag,
        address strategy
    )
        external
        returns (address basket)
    {
        // Checks
        if (baseAsset == address(0)) {
            revert Errors.ZeroAddress();
        }
        uint256 basketTokensLength = self.basketTokens.length;
        if (basketTokensLength >= _MAX_NUM_OF_BASKET_TOKENS) {
            revert BasketTokenMaxExceeded();
        }
        bytes32 basketId = keccak256(abi.encodePacked(bitFlag, strategy));
        if (self.basketIdToAddress[basketId] != address(0)) {
            revert BasketTokenAlreadyExists();
        }
        // Checks with external view calls
        if (!self.strategyRegistry.supportsBitFlag(bitFlag, strategy)) {
            revert StrategyRegistryDoesNotSupportStrategy();
        }
        AssetRegistry assetRegistry = AssetRegistry(self.assetRegistry);
        {
            if (assetRegistry.hasPausedAssets(bitFlag)) {
                revert AssetNotEnabled();
            }
            address[] memory assets = assetRegistry.getAssets(bitFlag);
            if (assets.length == 0) {
                revert AssetListEmpty();
            }
            basket = Clones.clone(self.basketTokenImplementation);
            _setBaseAssetIndex(self, basket, assets, baseAsset);
            self.basketTokens.push(basket);
            self.basketAssets[basket] = assets;
            self.basketIdToAddress[basketId] = basket;
            // The set default management fee will given to the zero address
            self.managementFees[basket] = self.managementFees[address(0)];
            uint256 assetsLength = assets.length;
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketAssetToIndexPlusOne[basket][assets[j]] = j + 1;
                unchecked {
                    // Overflow not possible: j is bounded by assets.length
                    ++j;
                }
            }
        }
        unchecked {
            // Overflow not possible: basketTokensLength is less than the constant _MAX_NUM_OF_BASKET_TOKENS
            self.basketTokenToIndexPlusOne[basket] = basketTokensLength + 1;
        }
        // Interactions
        BasketToken(basket).initialize(IERC20(baseAsset), basketName, symbol, bitFlag, strategy, address(assetRegistry));
    }

    /// @notice Proposes a rebalance for the given baskets. The rebalance is proposed if the difference between the
    /// target balance and the current balance of any asset in the basket is more than 500 USD.
    /// @param baskets Array of basket addresses to rebalance.
    // solhint-disable code-complexity
    // slither-disable-next-line cyclomatic-complexity
    function proposeRebalance(BasketManagerStorage storage self, address[] calldata baskets) external {
        // Checks
        // Revert if a rebalance is already in progress
        if (self.rebalanceStatus.status != Status.NOT_STARTED) {
            revert MustWaitForRebalanceToComplete();
        }
        // slither-disable-next-line timestamp
        if (block.timestamp - self.rebalanceStatus.timestamp < _REBALANCE_COOLDOWN_SEC) {
            revert TooEarlyToProposeRebalance();
        }

        // Effects
        self.rebalanceStatus.basketMask = _createRebalanceBitMask(self, baskets);
        self.rebalanceStatus.timestamp = uint40(block.timestamp);
        self.rebalanceStatus.status = Status.REBALANCE_PROPOSED;

        address assetRegistry = self.assetRegistry;
        uint64[][] memory basketTargetWeights = new uint64[][](baskets.length);

        // Interactions
        bool shouldRebalance = false;
        for (uint256 i = 0; i < baskets.length;) {
            // slither-disable-start calls-loop
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            basketTargetWeights[i] = BasketToken(basket).getTargetWeights();
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            if (assets.length == 0) {
                revert BasketTokenNotFound();
            }
            if (AssetRegistry(assetRegistry).hasPausedAssets(BasketToken(basket).bitFlag())) {
                revert AssetNotEnabled();
            }
            // Calculate current basket value
            (uint256[] memory balances, uint256 basketValue) = _calculateBasketValue(self, basket, assets);
            // Notify Basket Token of rebalance:
            (uint256 pendingDeposits, uint256 pendingRedeems) =
                BasketToken(basket).prepareForRebalance(self.managementFees[basket], self.feeCollector);
            if (pendingDeposits > 0) {
                shouldRebalance = true;
            }
            uint256 totalSupply;
            {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 baseAssetIndex = self.basketTokenToBaseAssetIndexPlusOne[basket] - 1;
                uint256 pendingDepositValue;
                // Process pending deposits and fulfill them
                (totalSupply, pendingDepositValue) = _processPendingDeposits(
                    self, basket, basketValue, balances[baseAssetIndex], pendingDeposits, baseAssetIndex
                );
                balances[baseAssetIndex] += pendingDeposits;
                basketValue += pendingDepositValue;
            }
            uint256 requiredWithdrawValue = 0;
            // Pre-process pending redemptions
            if (pendingRedeems > 0) {
                shouldRebalance = true;
                if (totalSupply > 0) {
                    // totalSupply cannot be 0 when pendingRedeems is greater than 0, as redemptions
                    // can only occur if there are issued shares (i.e., totalSupply > 0).
                    // Division-by-zero is not possible: totalSupply is greater than 0
                    requiredWithdrawValue = FixedPointMathLib.fullMulDiv(basketValue, pendingRedeems, totalSupply);
                    if (requiredWithdrawValue > basketValue) {
                        // This should never happen, but if it does, withdraw the entire basket value
                        requiredWithdrawValue = basketValue;
                    }
                    unchecked {
                        // Overflow not possible: requiredWithdrawValue is less than or equal to basketValue
                        basketValue -= requiredWithdrawValue;
                    }
                }
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.pendingRedeems[basket] = pendingRedeems;
            }
            uint256[] memory targetBalances = _calculateTargetBalances(
                self, basket, basketValue, requiredWithdrawValue, assets, basketTargetWeights[i]
            );
            if (_isRebalanceRequired(assets, balances, targetBalances)) {
                shouldRebalance = true;
            }
            // slither-disable-end calls-loop
            unchecked {
                // Overflow not possible: i is less than baskets.length
                ++i;
            }
        }
        if (!shouldRebalance) {
            revert RebalanceNotRequired();
        }
        // Effects after Interactions. Target weights require external view calls to respective strategies.
        bytes32 basketHash = keccak256(abi.encode(baskets, basketTargetWeights));
        self.rebalanceStatus.basketHash = basketHash;
        // slither-disable-next-line reentrancy-events
        emit RebalanceProposed(self.rebalanceStatus.epoch, baskets, basketTargetWeights, basketHash);
    }
    // solhint-enable code-complexity

    // @notice Proposes a set of internal trades and external trades to rebalance the given baskets.
    /// If the proposed token swap results are not close to the target balances, this function will revert.
    /// @dev This function can only be called after proposeRebalance.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param internalTrades Array of internal trades to execute.
    /// @param externalTrades Array of external trades to execute.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketTargetWeights Array of target weights for each basket.
    // slither-disable-next-line cyclomatic-complexity
    function proposeTokenSwap(
        BasketManagerStorage storage self,
        InternalTrade[] calldata internalTrades,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint64[][] calldata basketTargetWeights
    )
        external
    {
        // Checks
        RebalanceStatus memory status = self.rebalanceStatus;
        if (status.status != Status.REBALANCE_PROPOSED) {
            revert MustWaitForRebalanceToComplete();
        }
        _validateBasketHash(self, baskets, basketTargetWeights);

        // Effects
        status.timestamp = uint40(block.timestamp);
        status.status = Status.TOKEN_SWAP_PROPOSED;
        self.rebalanceStatus = status;
        self.externalTradesHash = keccak256(abi.encode(externalTrades));

        uint256 numBaskets = baskets.length;
        uint256[] memory totalValues = new uint256[](numBaskets);
        // 2d array of asset balances for each basket
        uint256[][] memory basketBalances = new uint256[][](numBaskets);
        _initializeBasketData(self, baskets, basketBalances, totalValues);
        // NOTE: for rebalance retries the internal trades must be updated as well
        _processInternalTrades(self, internalTrades, baskets, basketBalances);
        _validateExternalTrades(self, externalTrades, baskets, totalValues, basketBalances);
        if (!_isTargetWeightMet(self, baskets, basketBalances, totalValues, basketTargetWeights)) {
            revert TargetWeightsNotMet();
        }
    }

    /// @notice Completes the rebalance for the given baskets. The rebalance can be completed if it has been more than
    /// 15 minutes since the last action.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades matching those proposed for rebalance.
    /// @param baskets Array of basket addresses proposed for rebalance.
    /// @param basketTargetWeights Array of target weights for each basket.
    // slither-disable-next-line cyclomatic-complexity
    function completeRebalance(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint64[][] calldata basketTargetWeights
    )
        external
    {
        // Revert if there is no rebalance in progress
        // slither-disable-next-line incorrect-equality
        if (self.rebalanceStatus.status == Status.NOT_STARTED) {
            revert NoRebalanceInProgress();
        }
        _validateBasketHash(self, baskets, basketTargetWeights);
        // Check if the rebalance was proposed more than 15 minutes ago
        // slither-disable-next-line timestamp
        if (block.timestamp - self.rebalanceStatus.timestamp < 15 minutes) {
            revert TooEarlyToCompleteRebalance();
        }
        // if external trades are proposed and executed, finalize them and claim results from the trades
        if (self.rebalanceStatus.status == Status.TOKEN_SWAP_EXECUTED) {
            if (keccak256(abi.encode(externalTrades)) != self.externalTradesHash) {
                revert ExternalTradeMismatch();
            }
            _processExternalTrades(self, externalTrades);
        }

        uint256 len = baskets.length;
        uint256[] memory totalValue_ = new uint256[](len);
        // 2d array of asset amounts for each basket after all trades are settled
        uint256[][] memory afterTradeAmounts_ = new uint256[][](len);
        _initializeBasketData(self, baskets, afterTradeAmounts_, totalValue_);
        // Confirm that target weights have been met, if max retries is reached continue regardless
        if (self.retryCount < _MAX_RETRIES) {
            if (!_isTargetWeightMet(self, baskets, afterTradeAmounts_, totalValue_, basketTargetWeights)) {
                // If target weights are not met and we have not reached max retries, revert to beginning of rebalance
                // to allow for additional token swaps to be proposed and increment retryCount.
                self.retryCount += 1;
                self.rebalanceStatus.timestamp = uint40(block.timestamp);
                self.externalTradesHash = bytes32(0);
                self.rebalanceStatus.status = Status.REBALANCE_PROPOSED;
                return;
            }
        }
        _finalizeRebalance(self, baskets);
    }

    /// FALLBACK REDEEM LOGIC ///

    /// @notice Fallback redeem function to redeem shares when the rebalance is not in progress. Redeems the shares for
    /// each underlying asset in the basket pro-rata to the amount of shares redeemed.
    /// @param totalSupplyBefore Total supply of the basket token before the shares were burned.
    /// @param burnedShares Amount of shares burned.
    /// @param to Address to send the redeemed assets to.
    function proRataRedeem(
        BasketManagerStorage storage self,
        uint256 totalSupplyBefore,
        uint256 burnedShares,
        address to
    )
        external
    {
        // Checks
        if (totalSupplyBefore == 0) {
            revert ZeroTotalSupply();
        }
        if (burnedShares == 0) {
            revert ZeroBurnedShares();
        }
        if (burnedShares > totalSupplyBefore) {
            revert CannotBurnMoreSharesThanTotalSupply();
        }
        if (to == address(0)) {
            revert Errors.ZeroAddress();
        }
        // Revert if the basket is currently rebalancing
        if ((self.rebalanceStatus.basketMask & (1 << self.basketTokenToIndexPlusOne[msg.sender] - 1)) != 0) {
            revert MustWaitForRebalanceToComplete();
        }

        address basket = msg.sender;
        address[] storage assets = self.basketAssets[basket];
        uint256 assetsLength = assets.length;

        // Interactions
        for (uint256 i = 0; i < assetsLength;) {
            address asset = assets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 balance = self.basketBalanceOf[basket][asset];
            // Rounding direction: down
            // Division-by-zero is not possible: totalSupplyBefore is greater than 0
            uint256 amountToWithdraw = FixedPointMathLib.fullMulDiv(burnedShares, balance, totalSupplyBefore);
            if (amountToWithdraw > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[basket][asset] = balance - amountToWithdraw;
                // Asset is an allowlisted ERC20 with no reentrancy problem in transfer
                // slither-disable-next-line reentrancy-no-eth
                IERC20(asset).safeTransfer(to, amountToWithdraw);
            }
            unchecked {
                // Overflow not possible: i is less than assetsLength
                ++i;
            }
        }
    }

    /// @notice Returns the index of the asset in a given basket
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketToken Basket token address.
    /// @param asset Asset address.
    /// @return index Index of the asset in the basket.
    function basketTokenToRebalanceAssetToIndex(
        BasketManagerStorage storage self,
        address basketToken,
        address asset
    )
        public
        view
        returns (uint256 index)
    {
        index = self.basketAssetToIndexPlusOne[basketToken][asset];
        if (index == 0) {
            revert AssetNotFoundInBasket();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /// @notice Returns the index of the basket token.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basketToken Basket token address.
    /// @return index Index of the basket token.
    function basketTokenToIndex(
        BasketManagerStorage storage self,
        address basketToken
    )
        public
        view
        returns (uint256 index)
    {
        index = self.basketTokenToIndexPlusOne[basketToken];
        if (index == 0) {
            revert BasketTokenNotFound();
        }
        unchecked {
            // Overflow not possible: index is not 0
            return index - 1;
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Returns the index of the element in the array.
    /// @dev Reverts if the element does not exist in the array.
    /// @param array Array to find the element in.
    /// @param element Element to find in the array.
    /// @return index Index of the element in the array.
    function _indexOf(address[] memory array, address element) internal pure returns (uint256 index) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length;) {
            if (array[i] == element) {
                return i;
            }
            unchecked {
                // Overflow not possible: index is not 0
                ++i;
            }
        }
        revert ElementIndexNotFound();
    }

    /// PRIVATE FUNCTIONS ///

    /// @notice Internal function to finalize the state changes for the current rebalance. Resets rebalance status and
    /// attempts to process pending redeems. If all pending redeems cannot be fulfilled notifies basket token of a
    /// failed rebalance.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    function _finalizeRebalance(BasketManagerStorage storage self, address[] calldata baskets) private {
        // Advance the rebalance epoch and reset the status
        uint40 epoch = self.rebalanceStatus.epoch;
        self.rebalanceStatus.basketHash = bytes32(0);
        self.rebalanceStatus.basketMask = 0;
        self.rebalanceStatus.epoch += 1;
        self.rebalanceStatus.timestamp = uint40(block.timestamp);
        self.rebalanceStatus.status = Status.NOT_STARTED;
        self.externalTradesHash = bytes32(0);
        self.retryCount = 0;
        // slither-disable-next-line reentrancy-events
        emit RebalanceCompleted(epoch);

        // Process the redeems for the given baskets
        // slither-disable-start calls-loop
        uint256 len = baskets.length;
        for (uint256 i = 0; i < len;) {
            // NOTE: Can be optimized by using calldata for the `baskets` parameter or by moving the
            // redemption processing logic to a ZK coprocessor like Axiom for improved efficiency and scalability.
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            uint256[] memory balances = new uint256[](assetsLength);
            uint256 basketValue = 0;

            // Calculate current basket value
            for (uint256 j = 0; j < assetsLength;) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                balances[j] = self.basketBalanceOf[basket][assets[j]];
                // Rounding direction: down
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketValue += self.eulerRouter.getQuote(balances[j], assets[j], _USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }

            // If there are pending redeems, process them
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            uint256 pendingRedeems = self.pendingRedeems[basket];
            if (pendingRedeems > 0) {
                // slither-disable-next-line costly-loop
                delete self.pendingRedeems[basket]; // nosemgrep
                // Assume the first asset listed in the basket is the base asset
                // Rounding direction: down
                // Division-by-zero is not possible: priceOfAssets[baseAssetIndex] is greater than 0, totalSupply is
                // greater than 0
                // when pendingRedeems is greater than 0
                uint256 rawAmount =
                    FixedPointMathLib.fullMulDiv(basketValue, pendingRedeems, BasketToken(basket).totalSupply());
                uint256 baseAssetIndex = self.basketTokenToBaseAssetIndexPlusOne[basket] - 1;
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 withdrawAmount =
                    self.eulerRouter.getQuote(rawAmount, _USD_ISO_4217_CODE, assets[baseAssetIndex]);
                if (withdrawAmount <= balances[baseAssetIndex]) {
                    unchecked {
                        // Overflow not possible: withdrawAmount is less than or equal to balances[baseAssetIndex]
                        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                        self.basketBalanceOf[basket][assets[baseAssetIndex]] = balances[baseAssetIndex] - withdrawAmount;
                    }
                    // slither-disable-next-line reentrancy-no-eth
                    IERC20(assets[baseAssetIndex]).forceApprove(basket, withdrawAmount);
                    // ERC20.transferFrom is called in BasketToken.fulfillRedeem
                    // slither-disable-next-line reentrancy-no-eth
                    BasketToken(basket).fulfillRedeem(withdrawAmount);
                } else {
                    BasketToken(basket).fallbackRedeemTrigger();
                }
            }
            unchecked {
                // Overflow not possible: i is less than baskets.length
                ++i;
            }
        }
        // slither-disable-end calls-loop
    }

    /// @notice Internal function to complete proposed token swaps.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be completed.
    /// @return claimedAmounts amounts claimed from the completed token swaps
    function _completeTokenSwap(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades
    )
        private
        returns (uint256[2][] memory claimedAmounts)
    {
        // solhint-disable avoid-low-level-calls
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory data) =
            self.tokenSwapAdapter.delegatecall(abi.encodeCall(TokenSwapAdapter.completeTokenSwap, (externalTrades)));
        // solhint-enable avoid-low-level-calls
        if (!success) {
            // assume this low-level call never fails
            revert CompleteTokenSwapFailed();
        }
        claimedAmounts = abi.decode(data, (uint256[2][]));
    }

    /// @notice Internal function to update internal accounting with result of completed token swaps.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be completed.
    function _processExternalTrades(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades
    )
        private
    {
        uint256 externalTradesLength = externalTrades.length;
        uint256[2][] memory claimedAmounts = _completeTokenSwap(self, externalTrades);
        // Update basketBalanceOf with amounts gained from swaps
        for (uint256 i = 0; i < externalTradesLength;) {
            ExternalTrade memory trade = externalTrades[i];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 tradeOwnershipLength = trade.basketTradeOwnership.length;
            for (uint256 j; j < tradeOwnershipLength;) {
                BasketTradeOwnership memory ownership = trade.basketTradeOwnership[j];
                address basket = ownership.basket;
                // Account for bought tokens
                self.basketBalanceOf[basket][trade.buyToken] +=
                    FixedPointMathLib.fullMulDiv(claimedAmounts[i][1], ownership.tradeOwnership, _WEIGHT_PRECISION);
                // Account for sold tokens
                self.basketBalanceOf[basket][trade.sellToken] = self.basketBalanceOf[basket][trade.sellToken]
                    + FixedPointMathLib.fullMulDiv(claimedAmounts[i][0], ownership.tradeOwnership, _WEIGHT_PRECISION)
                    - FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, _WEIGHT_PRECISION);
                unchecked {
                    // Overflow not possible: i is less than tradeOwnerShipLength.length
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is less than externalTradesLength.length
                ++i;
            }
        }
    }

    /// @notice Internal function to initialize basket data.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketBalances An empty array used for asset balances for each basket being rebalanced. Updated with
    /// current balances at the end of the function.
    /// @param totalValue_ An initialized array of total basket values for each basket being rebalanced.
    function _initializeBasketData(
        BasketManagerStorage storage self,
        address[] calldata baskets,
        uint256[][] memory basketBalances,
        uint256[] memory totalValue_
    )
        private
        view
    {
        uint256 numBaskets = baskets.length;
        for (uint256 i = 0; i < numBaskets;) {
            address basket = baskets[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 assetsLength = assets.length;
            basketBalances[i] = new uint256[](assetsLength);
            for (uint256 j = 0; j < assetsLength;) {
                address asset = assets[j];
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                uint256 currentAssetAmount = self.basketBalanceOf[basket][asset];
                basketBalances[i][j] = currentAssetAmount;
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                totalValue_[i] += self.eulerRouter.getQuote(currentAssetAmount, asset, _USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is less than assetsLength
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is less than numBaskets
                ++i;
            }
        }
    }

    /// @notice Internal function to settle internal trades.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param internalTrades Array of internal trades to execute.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketBalances An initialized array of asset amounts for each basket being rebalanced. Updated with
    /// settled internal trades at the end of the function.
    /// @dev If the result of an internal trade is not within the provided minAmount or maxAmount, this function will
    /// revert.
    function _processInternalTrades(
        BasketManagerStorage storage self,
        InternalTrade[] calldata internalTrades,
        address[] calldata baskets,
        uint256[][] memory basketBalances
    )
        private
    {
        uint256 swapFee = self.swapFee; // Fetch swapFee once for gas optimization
        uint256 internalTradesLength = internalTrades.length;
        for (uint256 i = 0; i < internalTradesLength;) {
            InternalTrade memory trade = internalTrades[i];
            InternalTradeInfo memory info = InternalTradeInfo({
                fromBasketIndex: _indexOf(baskets, trade.fromBasket),
                toBasketIndex: _indexOf(baskets, trade.toBasket),
                sellTokenAssetIndex: basketTokenToRebalanceAssetToIndex(self, trade.fromBasket, trade.sellToken),
                buyTokenAssetIndex: basketTokenToRebalanceAssetToIndex(self, trade.fromBasket, trade.buyToken),
                toBasketBuyTokenIndex: basketTokenToRebalanceAssetToIndex(self, trade.toBasket, trade.buyToken),
                toBasketSellTokenIndex: basketTokenToRebalanceAssetToIndex(self, trade.toBasket, trade.sellToken),
                netBuyAmount: 0,
                netSellAmount: 0,
                feeOnBuy: 0,
                feeOnSell: 0
            });

            // Calculate fee on sellAmount
            if (swapFee > 0) {
                info.feeOnSell = FixedPointMathLib.fullMulDiv(trade.sellAmount, swapFee, 20_000);
                self.collectedSwapFees[trade.sellToken] += info.feeOnSell;
                emit SwapFeeCharged(trade.sellToken, info.feeOnSell);
            }
            info.netSellAmount = trade.sellAmount - info.feeOnSell;

            // Calculate initial buyAmount based on netSellAmount
            uint256 initialBuyAmount = self.eulerRouter.getQuote(
                self.eulerRouter.getQuote(info.netSellAmount, trade.sellToken, _USD_ISO_4217_CODE),
                _USD_ISO_4217_CODE,
                trade.buyToken
            );

            // Calculate fee on buyAmount
            if (swapFee > 0) {
                info.feeOnBuy = FixedPointMathLib.fullMulDiv(initialBuyAmount, swapFee, 20_000);
                self.collectedSwapFees[trade.buyToken] += info.feeOnBuy;
                emit SwapFeeCharged(trade.buyToken, info.feeOnBuy);
            }
            info.netBuyAmount = initialBuyAmount - info.feeOnBuy;

            if (info.netBuyAmount < trade.minAmount || trade.maxAmount < info.netBuyAmount) {
                revert InternalTradeMinMaxAmountNotReached();
            }
            if (trade.sellAmount > basketBalances[info.fromBasketIndex][info.sellTokenAssetIndex]) {
                revert IncorrectTradeTokenAmount();
            }
            if (info.netBuyAmount > basketBalances[info.toBasketIndex][info.toBasketBuyTokenIndex]) {
                revert IncorrectTradeTokenAmount();
            }

            // Settle the internal trades and track the balance changes.
            // This unchecked block is safe because:
            // - The subtraction operations can't underflow since the if checks above ensure the values being
            //   subtracted are less than or equal to the corresponding values in basketBalances.
            // - The addition operations can't overflow since the total supply of each token is limited and the
            //   amounts being added are always less than the total supply.
            unchecked {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[trade.fromBasket][trade.sellToken] =
                    basketBalances[info.fromBasketIndex][info.sellTokenAssetIndex] -= trade.sellAmount; // nosemgrep
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[trade.fromBasket][trade.buyToken] =
                    basketBalances[info.fromBasketIndex][info.buyTokenAssetIndex] += info.netBuyAmount; // nosemgrep
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[trade.toBasket][trade.buyToken] =
                    basketBalances[info.toBasketIndex][info.toBasketBuyTokenIndex] -= initialBuyAmount; // nosemgrep
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                self.basketBalanceOf[trade.toBasket][trade.sellToken] =
                    basketBalances[info.toBasketIndex][info.toBasketSellTokenIndex] += info.netSellAmount; // nosemgrep
                ++i;
            }
            emit InternalTradeSettled(trade, info.netBuyAmount);
        }
    }

    /// @notice Internal function to validate the results of external trades.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param externalTrades Array of external trades to be validated.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param totalValue_ Array of total basket values in USD.
    /// @param afterTradeAmounts_ An initialized array of asset amounts for each basket being rebalanced.
    /// @dev If the result of an external trade is not within the _MAX_SLIPPAGE threshold of the minAmount, this
    /// function will revert.
    function _validateExternalTrades(
        BasketManagerStorage storage self,
        ExternalTrade[] calldata externalTrades,
        address[] calldata baskets,
        uint256[] memory totalValue_,
        uint256[][] memory afterTradeAmounts_
    )
        private
        view
    {
        for (uint256 i = 0; i < externalTrades.length;) {
            ExternalTrade memory trade = externalTrades[i];
            // slither-disable-start uninitialized-local
            ExternalTradeInfo memory info;
            BasketOwnershipInfo memory ownershipInfo;
            // slither-disable-end uninitialized-local

            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            for (uint256 j = 0; j < trade.basketTradeOwnership.length;) {
                BasketTradeOwnership memory ownership = trade.basketTradeOwnership[j];
                ownershipInfo.basketIndex = _indexOf(baskets, ownership.basket);
                ownershipInfo.buyTokenAssetIndex =
                    basketTokenToRebalanceAssetToIndex(self, ownership.basket, trade.buyToken);
                ownershipInfo.sellTokenAssetIndex =
                    basketTokenToRebalanceAssetToIndex(self, ownership.basket, trade.sellToken);
                uint256 ownershipSellAmount =
                    FixedPointMathLib.fullMulDiv(trade.sellAmount, ownership.tradeOwnership, _WEIGHT_PRECISION);
                uint256 ownershipBuyAmount =
                    FixedPointMathLib.fullMulDiv(trade.minAmount, ownership.tradeOwnership, _WEIGHT_PRECISION);
                // Record changes in basket asset holdings due to the external trade
                if (
                    ownershipSellAmount
                        > afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex]
                ) {
                    revert IncorrectTradeTokenAmount();
                }
                // solhint-disable-next-line max-line-length
                afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.sellTokenAssetIndex] = afterTradeAmounts_[ownershipInfo
                    .basketIndex][ownershipInfo.sellTokenAssetIndex] - ownershipSellAmount;
                afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.buyTokenAssetIndex] =
                    afterTradeAmounts_[ownershipInfo.basketIndex][ownershipInfo.buyTokenAssetIndex] + ownershipBuyAmount;
                // Update total basket value
                totalValue_[ownershipInfo.basketIndex] = totalValue_[ownershipInfo.basketIndex]
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                - self.eulerRouter.getQuote(ownershipSellAmount, trade.sellToken, _USD_ISO_4217_CODE)
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                + self.eulerRouter.getQuote(ownershipBuyAmount, trade.buyToken, _USD_ISO_4217_CODE);
                unchecked {
                    // Overflow not possible: j is bounded by trade.basketTradeOwnership.length
                    ++j;
                }
            }
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.sellValue = self.eulerRouter.getQuote(trade.sellAmount, trade.sellToken, _USD_ISO_4217_CODE);
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            info.internalMinAmount = self.eulerRouter.getQuote(info.sellValue, _USD_ISO_4217_CODE, trade.buyToken);
            info.diff = MathUtils.diff(info.internalMinAmount, trade.minAmount);

            // Check if the given minAmount is within the _MAX_SLIPPAGE threshold of internalMinAmount
            if (info.internalMinAmount < trade.minAmount) {
                if (info.diff * _WEIGHT_PRECISION / info.internalMinAmount > _MAX_SLIPPAGE) {
                    revert ExternalTradeSlippage();
                }
            }
            unchecked {
                // Overflow not possible: i is bounded by baskets.length
                ++i;
            }
        }
    }

    /// @notice Validate the basket hash based on the given baskets and target weights.
    function _validateBasketHash(
        BasketManagerStorage storage self,
        address[] calldata baskets,
        uint64[][] calldata basketsTargetWeights
    )
        private
        view
    {
        // Validate the calldata hashes
        bytes32 basketHash = keccak256(abi.encode(baskets, basketsTargetWeights));
        if (self.rebalanceStatus.basketHash != basketHash) {
            revert BasketsMismatch();
        }
    }

    /// @notice Checks if weight deviations after trades are within the acceptable _MAX_WEIGHT_DEVIATION threshold.
    /// Returns true if all deviations are within bounds for each asset in every basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @param basketBalances 2D array of asset balances for each basket. Rows are baskets, columns are assets.
    /// @param totalValues Array of total basket values in USD.
    /// @param basketsTargetWeights Array of target weights for each basket.
    function _isTargetWeightMet(
        BasketManagerStorage storage self,
        address[] calldata baskets,
        uint256[][] memory basketBalances,
        uint256[] memory totalValues,
        uint64[][] calldata basketsTargetWeights
    )
        private
        view
        returns (bool)
    {
        // Check if total weight change due to all trades is within the _MAX_WEIGHT_DEVIATION threshold
        uint256 len = baskets.length;
        for (uint256 i = 0; i < len;) {
            address basket = baskets[i];
            // slither-disable-next-line calls-loop
            uint64[] memory proposedTargetWeights = basketsTargetWeights[i];
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            address[] memory assets = self.basketAssets[basket];
            // nosemgrep: solidity.performance.array-length-outside-loop.array-length-outside-loop
            uint256 proposedTargetWeightsLength = proposedTargetWeights.length;
            for (uint256 j = 0; j < proposedTargetWeightsLength;) {
                address asset = assets[j];
                uint256 assetValueInUSD =
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                 self.eulerRouter.getQuote(basketBalances[i][j], asset, _USD_ISO_4217_CODE);
                // Rounding direction: down
                uint256 afterTradeWeight =
                    FixedPointMathLib.fullMulDiv(assetValueInUSD, _WEIGHT_PRECISION, totalValues[i]);
                if (MathUtils.diff(proposedTargetWeights[j], afterTradeWeight) > _MAX_WEIGHT_DEVIATION) {
                    return false;
                }
                unchecked {
                    // Overflow not possible: j is bounded by proposedTargetWeightsLength
                    ++j;
                }
            }
            unchecked {
                // Overflow not possible: i is bounded by len
                ++i;
            }
        }
        return true;
    }

    /// @notice Internal function to process pending deposits and fulfill them.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param basketValue Current value of the basket in USD.
    /// @param baseAssetBalance Current balance of the base asset in the basket.
    /// @param pendingDeposit Current assets pending deposit in the given basket.
    /// @return totalSupply Total supply of the basket token after processing pending deposits.
    /// @return pendingDepositValue Value of the pending deposits in USD.
    // slither-disable-next-line calls-loop
    function _processPendingDeposits(
        BasketManagerStorage storage self,
        address basket,
        uint256 basketValue,
        uint256 baseAssetBalance,
        uint256 pendingDeposit,
        uint256 baseAssetIndex
    )
        private
        returns (uint256 totalSupply, uint256 pendingDepositValue)
    {
        totalSupply = BasketToken(basket).totalSupply();

        if (pendingDeposit > 0) {
            // Assume the first asset listed in the basket is the base asset
            // Round direction: down
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            pendingDepositValue =
                self.eulerRouter.getQuote(pendingDeposit, self.basketAssets[basket][baseAssetIndex], _USD_ISO_4217_CODE);
            // Rounding direction: down
            // Division-by-zero is not possible: basketValue is greater than 0
            uint256 requiredDepositShares = basketValue > 0
                ? FixedPointMathLib.fullMulDiv(pendingDepositValue, totalSupply, basketValue)
                : pendingDeposit;
            totalSupply += requiredDepositShares;
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            self.basketBalanceOf[basket][self.basketAssets[basket][baseAssetIndex]] = baseAssetBalance + pendingDeposit;
            // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
            BasketToken(basket).fulfillDeposit(requiredDepositShares);
        }
    }

    /// @notice Internal function to calculate the target balances for each asset in a given basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param basketValue Current value of the basket in USD.
    /// @param requiredWithdrawValue Value of the assets to be withdrawn from the basket.
    /// @param assets Array of asset addresses in the basket.
    /// @return targetBalances Array of target balances for each asset in the basket.
    // slither-disable-next-line calls-loop,naming-convention
    function _calculateTargetBalances(
        BasketManagerStorage storage self,
        address basket,
        uint256 basketValue,
        uint256 requiredWithdrawValue,
        address[] memory assets,
        uint64[] memory proposedTargetWeights
    )
        private
        view
        returns (uint256[] memory targetBalances)
    {
        uint256 assetsLength = assets.length;
        targetBalances = new uint256[](assetsLength);
        // Rounding direction: down
        // Division-by-zero is not possible: priceOfAssets[j] is greater than 0
        for (uint256 j = 0; j < assetsLength;) {
            if (proposedTargetWeights[j] > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                targetBalances[j] = self.eulerRouter.getQuote(
                    FixedPointMathLib.fullMulDiv(proposedTargetWeights[j], basketValue, _WEIGHT_PRECISION),
                    _USD_ISO_4217_CODE,
                    assets[j]
                );
            }
            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
        // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
        uint256 baseAssetIndex = self.basketTokenToBaseAssetIndexPlusOne[basket] - 1;
        if (requiredWithdrawValue > 0) {
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            targetBalances[baseAssetIndex] +=
                self.eulerRouter.getQuote(requiredWithdrawValue, _USD_ISO_4217_CODE, assets[baseAssetIndex]);
        }
    }

    /// @notice Internal function to calculate the current value of all assets in a given basket.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param assets Array of asset addresses in the basket.
    /// @return balances Array of balances of each asset in the basket.
    /// @return basketValue Current value of the basket in USD.
    // slither-disable-next-line calls-loop
    function _calculateBasketValue(
        BasketManagerStorage storage self,
        address basket,
        address[] memory assets
    )
        private
        view
        returns (uint256[] memory balances, uint256 basketValue)
    {
        uint256 assetsLength = assets.length;
        balances = new uint256[](assetsLength);
        for (uint256 j = 0; j < assetsLength;) {
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            balances[j] = self.basketBalanceOf[basket][assets[j]];
            // Rounding direction: down
            // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
            if (balances[j] > 0) {
                // nosemgrep: solidity.performance.state-variable-read-in-a-loop.state-variable-read-in-a-loop
                basketValue += self.eulerRouter.getQuote(balances[j], assets[j], _USD_ISO_4217_CODE);
            }
            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
    }

    /// @notice Internal function to check if a rebalance is required for the given basket.
    /// @dev A rebalance is required if the difference between the current asset balances and the target balances is
    /// greater than 0. We assume the permissioned caller has already validated the condition to call this function
    /// optimally.
    /// @param assets Array of asset addresses in the basket.
    /// @param balances Array of balances of each asset in the basket.
    /// @param targetBalances Array of target balances for each asset in the basket.
    /// @return shouldRebalance Boolean indicating if a rebalance is required.
    function _isRebalanceRequired(
        address[] memory assets,
        uint256[] memory balances,
        uint256[] memory targetBalances
    )
        private
        view
        returns (bool shouldRebalance)
    {
        uint256 assetsLength = assets.length;
        for (uint256 j = 0; j < assetsLength;) {
            // slither-disable-start calls-loop
            if (
                MathUtils.diff(balances[j], targetBalances[j]) > 0 // nosemgrep
            ) {
                shouldRebalance = true;
                break;
            }
            // slither-disable-end calls-loop
            unchecked {
                // Overflow not possible: j is less than assetsLength
                ++j;
            }
        }
    }

    /// @notice Internal function to store the index of the base asset for a given basket. Reverts if the base asset is
    /// not present in the basket's assets.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param basket Basket token address.
    /// @param assets Array of asset addresses in the basket.
    /// @param baseAsset Base asset address.
    /// @dev If the base asset is not present in the basket, this function will revert.
    function _setBaseAssetIndex(
        BasketManagerStorage storage self,
        address basket,
        address[] memory assets,
        address baseAsset
    )
        private
    {
        uint256 len = assets.length;
        for (uint256 i = 0; i < len;) {
            if (assets[i] == baseAsset) {
                self.basketTokenToBaseAssetIndexPlusOne[basket] = i + 1;
                return;
            }
            unchecked {
                // Overflow not possible: i is less than len
                ++i;
            }
        }
        revert BaseAssetMismatch();
    }

    /// @notice Internal function to create a bitmask for baskets being rebalanced.
    /// @param self BasketManagerStorage struct containing strategy data.
    /// @param baskets Array of basket addresses currently being rebalanced.
    /// @return basketMask Bitmask for baskets being rebalanced.
    /// @dev A bitmask like 00000011 indicates that the first two baskets are being rebalanced.
    function _createRebalanceBitMask(
        BasketManagerStorage storage self,
        address[] memory baskets
    )
        private
        view
        returns (uint256 basketMask)
    {
        // Create the bitmask for baskets being rebalanced
        basketMask = 0;
        uint256 len = baskets.length;
        for (uint256 i = 0; i < len;) {
            uint256 indexPlusOne = self.basketTokenToIndexPlusOne[baskets[i]];
            if (indexPlusOne == 0) {
                revert BasketTokenNotFound();
            }
            basketMask |= (1 << indexPlusOne - 1);
            unchecked {
                // Overflow not possible: i is less than len
                ++i;
            }
        }
    }
}
