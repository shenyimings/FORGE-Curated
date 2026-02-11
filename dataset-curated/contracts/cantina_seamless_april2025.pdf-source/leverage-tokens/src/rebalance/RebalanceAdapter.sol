// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal imports
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {ICollateralRatiosRebalanceAdapter} from "src/interfaces/ICollateralRatiosRebalanceAdapter.sol";
import {IRebalanceAdapterBase} from "src/interfaces/IRebalanceAdapterBase.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {DutchAuctionRebalanceAdapter} from "src/rebalance/DutchAuctionRebalanceAdapter.sol";
import {CollateralRatiosRebalanceAdapter} from "src/rebalance/CollateralRatiosRebalanceAdapter.sol";
import {PreLiquidationRebalanceAdapter} from "src/rebalance/PreLiquidationRebalanceAdapter.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

/**
 * @dev The RebalanceAdapter contract is an upgradeable periphery contract that implements the IRebalanceAdapter interface.
 * LeverageTokens configured on the LeverageManager must specify a RebalanceAdapter, which defines hooks for determining
 * when a LeverageToken can be rebalanced and if a rebalance action is valid, and how rebalancers should be rewarded.
 *
 * This RebalanceAdapter utilizes the DutchAuctionRebalanceAdapter, MinMaxCollateralRatioRebalanceAdapter, and
 * PreLiquidationRebalanceAdapter abstract contracts.
 *   - The DutchAuctionRebalanceAdapter creates Dutch auctions to determine the price of a rebalance action
 *   - The MinMaxCollateralRatioRebalanceAdapter ensures that the collateral ratio of a LeverageToken must be outside
 *     of a specified range before a rebalance action can be performed.
 *   - The PreLiquidationRebalanceAdapter allows for fast-tracking rebalance operations for LeverageTokens that are below
 *     a specified collateral ratio threshold. The intention is that this acts as a pre-liquidation rebalance mechanism
 *     in cases that the dutch auction price is too slow to react to a dramatic drop in collateral ratio.
 */
contract RebalanceAdapter is
    IRebalanceAdapter,
    UUPSUpgradeable,
    OwnableUpgradeable,
    CollateralRatiosRebalanceAdapter,
    DutchAuctionRebalanceAdapter,
    PreLiquidationRebalanceAdapter
{
    /// @dev Struct containing all state for the RebalanceAdapter contract
    /// @custom:storage-location erc7201:seamless.contracts.storage.RebalanceAdapter
    struct RebalanceAdapterStorage {
        /// @notice The authorized creator of this rebalance adapter. The authorized creator can create a
        ///         new leverage token using this adapter on the LeverageManager
        address authorizedCreator;
        /// @notice The LeverageManager contract
        ILeverageManager leverageManager;
    }

    function _getRebalanceAdapterStorage() internal pure returns (RebalanceAdapterStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.RebalanceAdapter")) - 1)) & ~bytes32(uint256(0xff));
            $.slot := 0xb8978c109109e89ddaa83c20e08d73ed7aedae610788761a7cdcbd1d2ce42300
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    struct RebalanceAdapterInitParams {
        /// @notice The owner of the rebalance adapter
        address owner;
        /// @notice The authorized creator of the rebalance adapter
        address authorizedCreator;
        /// @notice The LeverageManager contract
        ILeverageManager leverageManager;
        /// @notice The minimum collateral ratio for the rebalance adapter
        uint256 minCollateralRatio;
        /// @notice The target collateral ratio for the rebalance adapter
        uint256 targetCollateralRatio;
        /// @notice The maximum collateral ratio for the rebalance adapter
        uint256 maxCollateralRatio;
        /// @notice The duration of the auction for the rebalance adapter
        uint256 auctionDuration;
        /// @notice The initial price multiplier for the rebalance adapter
        uint256 initialPriceMultiplier;
        /// @notice The minimum price multiplier for the rebalance adapter
        uint256 minPriceMultiplier;
        /// @notice The collateral ratio threshold for the pre-liquidation rebalance adapter
        uint256 preLiquidationCollateralRatioThreshold;
        /// @notice The rebalance reward for the rebalance adapter
        uint256 rebalanceReward;
    }

    function initialize(RebalanceAdapterInitParams memory params) external initializer {
        __DutchAuctionRebalanceAdapter_init_unchained(
            params.auctionDuration, params.initialPriceMultiplier, params.minPriceMultiplier
        );
        __CollateralRatiosRebalanceAdapter_init_unchained(
            params.minCollateralRatio, params.targetCollateralRatio, params.maxCollateralRatio
        );
        __PreLiquidationRebalanceAdapter_init_unchained(
            params.preLiquidationCollateralRatioThreshold, params.rebalanceReward
        );
        __Ownable_init_unchained(params.owner);

        _getRebalanceAdapterStorage().authorizedCreator = params.authorizedCreator;
        _getRebalanceAdapterStorage().leverageManager = params.leverageManager;
        emit RebalanceAdapterInitialized(params.authorizedCreator, params.leverageManager);
    }

    /// @inheritdoc IRebalanceAdapterBase
    function postLeverageTokenCreation(address creator, address leverageToken) external {
        if (msg.sender != address(getLeverageManager())) revert Unauthorized();
        if (creator != getAuthorizedCreator()) revert Unauthorized();
        _setLeverageToken(ILeverageToken(leverageToken));
    }

    /// @inheritdoc IRebalanceAdapter
    function getAuthorizedCreator() public view returns (address) {
        return _getRebalanceAdapterStorage().authorizedCreator;
    }

    /// @inheritdoc IRebalanceAdapter
    function getLeverageManager()
        public
        view
        override(
            IRebalanceAdapter,
            DutchAuctionRebalanceAdapter,
            CollateralRatiosRebalanceAdapter,
            PreLiquidationRebalanceAdapter
        )
        returns (ILeverageManager)
    {
        return _getRebalanceAdapterStorage().leverageManager;
    }

    /// @inheritdoc IRebalanceAdapterBase
    function getLeverageTokenInitialCollateralRatio(ILeverageToken token)
        public
        view
        override(IRebalanceAdapterBase, CollateralRatiosRebalanceAdapter)
        returns (uint256)
    {
        return super.getLeverageTokenInitialCollateralRatio(token);
    }

    /// @inheritdoc IDutchAuctionRebalanceAdapter
    function getLeverageTokenTargetCollateralRatio()
        public
        view
        override(DutchAuctionRebalanceAdapter, CollateralRatiosRebalanceAdapter)
        returns (uint256 targetCollateralRatio)
    {
        return super.getLeverageTokenTargetCollateralRatio();
    }

    /// @inheritdoc IRebalanceAdapterBase
    function isEligibleForRebalance(ILeverageToken token, LeverageTokenState memory state, address caller)
        public
        view
        override(
            IRebalanceAdapterBase,
            DutchAuctionRebalanceAdapter,
            CollateralRatiosRebalanceAdapter,
            PreLiquidationRebalanceAdapter
        )
        returns (bool)
    {
        return (
            (
                DutchAuctionRebalanceAdapter.isEligibleForRebalance(token, state, caller)
                    && CollateralRatiosRebalanceAdapter.isEligibleForRebalance(token, state, caller)
            ) || PreLiquidationRebalanceAdapter.isEligibleForRebalance(token, state, caller)
        );
    }

    /// @inheritdoc IRebalanceAdapterBase
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        public
        view
        override(
            IRebalanceAdapterBase,
            DutchAuctionRebalanceAdapter,
            CollateralRatiosRebalanceAdapter,
            PreLiquidationRebalanceAdapter
        )
        returns (bool)
    {
        return (
            CollateralRatiosRebalanceAdapter.isStateAfterRebalanceValid(token, stateBefore)
                && PreLiquidationRebalanceAdapter.isStateAfterRebalanceValid(token, stateBefore)
        );
    }
}
