// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Internal imports
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ICollateralRatiosRebalanceAdapter} from "src/interfaces/ICollateralRatiosRebalanceAdapter.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

/**
 * @dev The CollateralRatiosRebalanceAdapter is an abstract contract that implements the ICollateralRatiosRebalanceAdapter interface.
 *
 * The CollateralRatiosRebalanceAdapter is initialized for a LeverageToken with a minimum collateral ratio, target collateral ratio, and maximum collateral ratio.
 *
 * The `isEligibleForRebalance` function will return true if the current collateral ratio of the LeverageToken is below the configured
 * minimum collateral ratio or above the configured maximum collateral ratio, allowing for a rebalance action to be performed on the LeverageToken.
 *
 * The `isStateAfterRebalanceValid` function will return true if the collateral ratio is better than before:
 *  - The collateral ratio is closer to the target collateral ratio than before
 *  - If the collateral ratio was below the target collateral ratio, the collateral ratio is still below the target collateral ratio or equal to it
 *  - If the collateral ratio was above the target collateral ratio, the collateral ratio is still above the target collateral ratio or equal to it
 */
abstract contract CollateralRatiosRebalanceAdapter is ICollateralRatiosRebalanceAdapter, Initializable {
    /// @dev Struct containing all state for the CollateralRatiosRebalanceAdapter contract
    /// @custom:storage-location erc7201:seamless.contracts.storage.CollateralRatiosRebalanceAdapter
    struct CollateralRatiosRebalanceAdapterStorage {
        /// @dev Minimum collateral ratio for a leverage token, immutable
        uint256 minCollateralRatio;
        /// @dev Target collateral ratio for a leverage token, immutable
        uint256 targetCollateralRatio;
        /// @dev Maximum collateral ratio for a leverage token, immutable
        uint256 maxCollateralRatio;
    }

    function _getCollateralRatiosRebalanceAdapterStorage()
        internal
        pure
        returns (CollateralRatiosRebalanceAdapterStorage storage $)
    {
        // slither-disable-next-line assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.CollateralRatiosRebalanceAdapter")) - 1)) & ~bytes32(uint256(0xff));
            $.slot := 0x0c0c36e5d849345ad68de971568490058599308849c5c9b43b43ea5781d51300
        }
    }

    function __CollateralRatiosRebalanceAdapter_init(
        uint256 minCollateralRatio,
        uint256 targetCollateralRatio,
        uint256 maxCollateralRatio
    ) internal onlyInitializing {
        __CollateralRatiosRebalanceAdapter_init_unchained(minCollateralRatio, targetCollateralRatio, maxCollateralRatio);
    }

    function __CollateralRatiosRebalanceAdapter_init_unchained(
        uint256 minCollateralRatio,
        uint256 targetCollateralRatio,
        uint256 maxCollateralRatio
    ) internal onlyInitializing {
        bool areRatiosValid = minCollateralRatio <= targetCollateralRatio && targetCollateralRatio <= maxCollateralRatio;
        if (!areRatiosValid) {
            revert InvalidCollateralRatios();
        }

        _getCollateralRatiosRebalanceAdapterStorage().minCollateralRatio = minCollateralRatio;
        _getCollateralRatiosRebalanceAdapterStorage().targetCollateralRatio = targetCollateralRatio;
        _getCollateralRatiosRebalanceAdapterStorage().maxCollateralRatio = maxCollateralRatio;

        emit CollateralRatiosRebalanceAdapterInitialized(minCollateralRatio, targetCollateralRatio, maxCollateralRatio);
    }

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function getLeverageManager() public view virtual returns (ILeverageManager);

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function getLeverageTokenMinCollateralRatio() public view returns (uint256) {
        return _getCollateralRatiosRebalanceAdapterStorage().minCollateralRatio;
    }

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function getLeverageTokenTargetCollateralRatio() public view virtual returns (uint256) {
        return _getCollateralRatiosRebalanceAdapterStorage().targetCollateralRatio;
    }

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function getLeverageTokenMaxCollateralRatio() public view returns (uint256) {
        return _getCollateralRatiosRebalanceAdapterStorage().maxCollateralRatio;
    }

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function getLeverageTokenInitialCollateralRatio(ILeverageToken) public view virtual returns (uint256) {
        return getLeverageTokenTargetCollateralRatio();
    }

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function isEligibleForRebalance(ILeverageToken, LeverageTokenState memory state, address)
        public
        view
        virtual
        returns (bool isEligible)
    {
        uint256 minCollateralRatio = getLeverageTokenMinCollateralRatio();
        uint256 maxCollateralRatio = getLeverageTokenMaxCollateralRatio();

        if (state.collateralRatio >= minCollateralRatio && state.collateralRatio <= maxCollateralRatio) {
            return false;
        }

        return true;
    }

    /// @inheritdoc ICollateralRatiosRebalanceAdapter
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        public
        view
        virtual
        returns (bool isValid)
    {
        uint256 targetRatio = getLeverageTokenTargetCollateralRatio();
        LeverageTokenState memory stateAfter = getLeverageManager().getLeverageTokenState(token);

        uint256 ratioBefore = stateBefore.collateralRatio;
        uint256 ratioAfter = stateAfter.collateralRatio;

        uint256 minRatioAfter = ratioBefore > targetRatio ? targetRatio : ratioBefore;
        uint256 maxRatioAfter = ratioBefore > targetRatio ? ratioBefore : targetRatio;

        if (ratioAfter < minRatioAfter || ratioAfter > maxRatioAfter) {
            return false;
        }

        return true;
    }
}
