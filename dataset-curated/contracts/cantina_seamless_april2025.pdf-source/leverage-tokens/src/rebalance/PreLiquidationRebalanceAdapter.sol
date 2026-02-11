// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {IPreLiquidationLendingAdapter} from "src/interfaces/IPreLiquidationLendingAdapter.sol";
import {IPreLiquidationRebalanceAdapter} from "src/interfaces/IPreLiquidationRebalanceAdapter.sol";

/**
 * @dev The PreLiquidationRebalanceAdapter is an abstract contract that implements the IPreLiquidationRebalanceAdapter interface.
 * It is intended to be used to create pre-liquidation rebalance mechanisms for LeverageTokens.
 *
 * The PreLiquidationRebalanceAdapter is initialized for a LeverageToken with a collateral ratio threshold and a rebalance reward.
 * The `isEligibleForRebalance` function will return true if the current collateral ratio of the LeverageToken is below the configured
 * collateral ratio threshold, allowing for a rebalance action to be performed on LeverageToken on the LeverageManager.
 *
 * The PreLiquidationRebalanceAdapter is also initialized with a rebalance reward, which is a flat percentage that is applied to the
 * liquidation penalty of the underlying lending pool used by the LeverageToken. The result is the amount of equity that the rebalancer
 * can earn for rebalancing the LeverageToken. It is expected that the rebalance reward is set to a value that is less than the liquidation penalty,
 * but high enough such that rebalancing is attractive to rebalancers.
 */
abstract contract PreLiquidationRebalanceAdapter is Initializable, IPreLiquidationRebalanceAdapter {
    uint256 internal constant WAD = 1e18;
    /// @notice Reward base, 100_00 means that the reward is 100%
    uint256 public constant REWARD_BASE = 1e4;

    /// @dev Struct containing all state for the PreLiquidationRebalanceAdapter contract
    /// @custom:storage-location erc7201:seamless.contracts.storage.PreLiquidationRebalanceAdapter
    struct PreLiquidationRebalanceAdapterStorage {
        /// @notice Collateral ratio threshold to allow pre-liquidation rebalance. If collateral ratio is below this threshold,
        /// rebalance is allowed
        uint256 collateralRatioThreshold;
        /// @notice Rebalance reward, a flat percentage of the liquidation penalty that a rebalancer can take from the equity of the LeverageToken
        /// @dev The percentage is applied to the debt repaid by the rebalancer that they can take from the equity of the LeverageToken
        /// @dev 100_00 = 100%
        uint256 rebalanceReward;
    }

    function _getPreLiquidationRebalanceAdapterStorage()
        internal
        pure
        returns (PreLiquidationRebalanceAdapterStorage storage $)
    {
        assembly {
            // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.PreLiquidationRebalanceAdapter")) - 1)) & ~bytes32(uint256(0xff));
            $.slot := 0xb16e43fdb4a23e2eb5ac7d6fe250e1e010c7a5096910e708d8b2faba66b7d800
        }
    }

    function __PreLiquidationRebalanceAdapter_init(uint256 collateralRatioThreshold, uint256 rebalanceReward)
        internal
        onlyInitializing
    {
        __PreLiquidationRebalanceAdapter_init_unchained(collateralRatioThreshold, rebalanceReward);
    }

    function __PreLiquidationRebalanceAdapter_init_unchained(uint256 collateralRatioThreshold, uint256 rebalanceReward)
        internal
        onlyInitializing
    {
        _getPreLiquidationRebalanceAdapterStorage().collateralRatioThreshold = collateralRatioThreshold;
        _getPreLiquidationRebalanceAdapterStorage().rebalanceReward = rebalanceReward;
        emit PreLiquidationRebalanceAdapterInitialized(collateralRatioThreshold, rebalanceReward);
    }

    /// @inheritdoc IPreLiquidationRebalanceAdapter
    function getLeverageManager() public view virtual returns (ILeverageManager);

    /// @inheritdoc IPreLiquidationRebalanceAdapter
    function getCollateralRatioThreshold() public view returns (uint256) {
        return _getPreLiquidationRebalanceAdapterStorage().collateralRatioThreshold;
    }

    /// @inheritdoc IPreLiquidationRebalanceAdapter
    function getRebalanceReward() public view returns (uint256) {
        return _getPreLiquidationRebalanceAdapterStorage().rebalanceReward;
    }

    /// @inheritdoc IPreLiquidationRebalanceAdapter
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        public
        view
        virtual
        returns (bool)
    {
        // If the leverage token was rebalanced before meeting the collateral ratio threshold for a pre-liquidation rebalance, simply return true
        if (stateBefore.collateralRatio >= getCollateralRatioThreshold()) {
            return true;
        }

        ILeverageManager leverageManager = getLeverageManager();
        IPreLiquidationLendingAdapter lendingAdapter =
            IPreLiquidationLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(token)));

        LeverageTokenState memory stateAfter = leverageManager.getLeverageTokenState(token);
        uint256 liquidationPenalty = lendingAdapter.getLiquidationPenalty();

        uint256 rebalanceRewardPercentage = Math.mulDiv(liquidationPenalty, getRebalanceReward(), REWARD_BASE);

        // Scenario where debt after is bigger than debt before is scenario where user is adding collateral and borrowing debt
        // Collateral ratio must increase after rebalance and increasing is with adding collateral and borrowing debt is highly unprofitable
        // That means that this scenario is highly unlikely but we support it with this check

        uint256 debtDelta =
            stateBefore.debt > stateAfter.debt ? stateBefore.debt - stateAfter.debt : stateAfter.debt - stateBefore.debt;

        uint256 maxEquityLoss = Math.mulDiv(debtDelta, rebalanceRewardPercentage, WAD);
        return stateAfter.equity >= stateBefore.equity - maxEquityLoss;
    }

    /// @inheritdoc IPreLiquidationRebalanceAdapter
    function isEligibleForRebalance(ILeverageToken, /*token*/ LeverageTokenState memory state, address)
        public
        view
        virtual
        returns (bool)
    {
        return state.collateralRatio < getCollateralRatioThreshold();
    }
}
