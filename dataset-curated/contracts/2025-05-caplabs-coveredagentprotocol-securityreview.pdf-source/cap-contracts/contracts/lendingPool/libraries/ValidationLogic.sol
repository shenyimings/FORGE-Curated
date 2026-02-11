// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IDelegation } from "../../interfaces/IDelegation.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILender } from "../../interfaces/ILender.sol";
import { ViewLogic } from "./ViewLogic.sol";

/// @title Validation Logic
/// @author kexley, @capLabs
/// @notice Validate actions before state is altered
library ValidationLogic {
    /// @dev Collateral cannot cover new borrow
    error CollateralCannotCoverNewBorrow();

    /// @dev Health factor not below threshold
    error HealthFactorNotBelowThreshold();

    /// @dev Health factor lower than liquidation threshold
    error HealthFactorLowerThanLiquidationThreshold(uint256 health);

    /// @dev Already initiated
    error AlreadyInitiated();

    /// @dev Grace period not over
    error GracePeriodNotOver();

    /// @dev Liquidation expired
    error LiquidationExpired();

    /// @dev Reserve paused
    error ReservePaused();

    /// @dev Asset not listed
    error AssetNotListed();

    /// @dev Variable debt supply not zero
    error VariableDebtSupplyNotZero();

    /// @dev Zero address not valid
    error ZeroAddressNotValid();

    /// @dev Reserve already initialized
    error ReserveAlreadyInitialized();

    /// @dev Interest receiver not set
    error InterestReceiverNotSet();

    /// @dev Restaker interest receiver not set
    error RestakerInterestReceiverNotSet();

    /// @dev Minimum borrow amount
    error MinBorrowAmount();

    /// @notice Validate the borrow of an agent
    /// @dev Check the pause state of the reserve and the health of the agent before and after the
    /// borrow.
    /// @param $ Lender storage
    /// @param params Validation parameters
    function validateBorrow(ILender.LenderStorage storage $, ILender.BorrowParams memory params) external {
        if (params.amount < $.reservesData[params.asset].minBorrow) revert MinBorrowAmount();
        if (params.receiver == address(0) || params.asset == address(0)) revert ZeroAddressNotValid();
        if ($.reservesData[params.asset].paused) revert ReservePaused();

        uint256 borrowCapacity = ViewLogic.maxBorrowable($, params.agent, params.asset);

        if (params.amount > borrowCapacity) revert CollateralCannotCoverNewBorrow();

        IDelegation($.delegation).setLastBorrow(params.agent);
    }

    /// @notice Validate the initialization of the liquidation of an agent
    /// @dev Health of above 1e27 is healthy, below is liquidatable
    /// @param health Health of an agent's position
    /// @param start Last liquidation start time
    /// @param expiry Liquidation duration after which it expires
    function validateInitiateLiquidation(uint256 health, uint256 start, uint256 expiry) external view {
        if (health >= 1e27) revert HealthFactorNotBelowThreshold();
        if (block.timestamp <= start + expiry) revert AlreadyInitiated();
    }

    /// @notice Validate the cancellation of the liquidation of an agent
    /// @dev Health of above 1e27 is healthy, below is liquidatable
    /// @param health Health of an agent's position
    function validateCancelLiquidation(uint256 health) external pure {
        if (health < 1e27) revert HealthFactorLowerThanLiquidationThreshold(health);
    }

    /// @notice Validate the liquidation of an agent
    /// @dev Health of above 1e27 is healthy, below is liquidatable
    /// @param health Health of an agent's position
    /// @param emergencyHealth Emergency health below which the grace period is voided
    /// @param start Last liquidation start time
    /// @param grace Grace period duration
    /// @param expiry Liquidation duration after which it expires
    function validateLiquidation(uint256 health, uint256 emergencyHealth, uint256 start, uint256 grace, uint256 expiry)
        external
        view
    {
        if (health >= 1e27) revert HealthFactorNotBelowThreshold();
        if (emergencyHealth >= 1e27) {
            if (block.timestamp <= start + grace) revert GracePeriodNotOver();
            if (block.timestamp >= start + expiry) revert LiquidationExpired();
        }
    }

    /// @notice Validate adding an asset as a reserve
    /// @param $ Lender storage
    /// @param params Parameters for adding an asset
    function validateAddAsset(ILender.LenderStorage storage $, ILender.AddAssetParams memory params) external view {
        if (params.asset == address(0) || params.vault == address(0)) revert ZeroAddressNotValid();
        if (params.interestReceiver == address(0)) revert InterestReceiverNotSet();
        if (params.restakerInterestReceiver == address(0)) revert RestakerInterestReceiverNotSet();
        if ($.reservesData[params.asset].vault != address(0)) revert ReserveAlreadyInitialized();
    }

    /// @notice Validate dropping an asset as a reserve
    /// @dev All principal borrows must be repaid, interest is ignored
    /// @param $ Lender storage
    /// @param _asset Asset to remove
    function validateRemoveAsset(ILender.LenderStorage storage $, address _asset) external view {
        if (IERC20($.reservesData[_asset].debtToken).totalSupply() != 0) revert VariableDebtSupplyNotZero();
    }

    /// @notice Validate pausing a reserve
    /// @param $ Lender storage
    /// @param _asset Asset to pause
    function validatePauseAsset(ILender.LenderStorage storage $, address _asset) external view {
        if ($.reservesData[_asset].vault == address(0)) revert AssetNotListed();
    }

    /// @notice Validate setting the minimum borrow amount
    /// @param $ Lender storage
    /// @param _asset Asset to set minimum borrow amount
    function validateSetMinBorrow(ILender.LenderStorage storage $, address _asset) external view {
        if ($.reservesData[_asset].vault == address(0)) revert AssetNotListed();
    }
}
