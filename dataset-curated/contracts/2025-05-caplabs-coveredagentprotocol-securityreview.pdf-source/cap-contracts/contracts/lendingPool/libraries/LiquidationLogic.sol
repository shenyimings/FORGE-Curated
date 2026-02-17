// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IDelegation } from "../../interfaces/IDelegation.sol";
import { IOracle } from "../../interfaces/IOracle.sol";

import { ILender } from "../../interfaces/ILender.sol";
import { BorrowLogic } from "./BorrowLogic.sol";
import { ValidationLogic } from "./ValidationLogic.sol";
import { ViewLogic } from "./ViewLogic.sol";

/// @title Liquidation Logic
/// @author kexley, @capLabs
/// @notice Liquidate an agent that has an unhealthy ltv by slashing their delegation backing
library LiquidationLogic {
    /// @dev Zero address not valid
    error ZeroAddressNotValid();

    /// @notice A liquidation has been initiated against an agent
    event InitiateLiquidation(address agent);

    /// @notice A liquidation has been cancelled
    event CancelLiquidation(address agent);

    /// @notice An agent has been liquidated
    event Liquidate(address indexed agent, address indexed liquidator, address asset, uint256 amount, uint256 value);

    /// @notice Initiate the liquidation of an agent if unhealthy
    /// @param $ Lender storage
    /// @param _agent Agent address
    function initiateLiquidation(ILender.LenderStorage storage $, address _agent) external {
        if (_agent == address(0)) revert ZeroAddressNotValid();
        (,,,, uint256 health) = ViewLogic.agent($, _agent);

        ValidationLogic.validateInitiateLiquidation(health, $.liquidationStart[_agent], $.expiry);

        $.liquidationStart[_agent] = block.timestamp;

        emit InitiateLiquidation(_agent);
    }

    /// @notice Cancel the liquidation of an agent if healthy
    /// @param $ Lender storage
    /// @param _agent Agent address
    function cancelLiquidation(ILender.LenderStorage storage $, address _agent) external {
        if (_agent == address(0)) revert ZeroAddressNotValid();
        (,,,, uint256 health) = ViewLogic.agent($, _agent);

        ValidationLogic.validateCancelLiquidation(health);

        $.liquidationStart[_agent] = 0;

        emit CancelLiquidation(_agent);
    }

    /// @notice Liquidate an agent when their health is below 1
    /// @dev Liquidation must be initiated first and the grace period must have passed. Liquidation
    /// bonus linearly increases, once grace period has ended, up to the cap at expiry.
    /// All health factors, LTV ratios, and thresholds are in ray (1e27)
    /// @param $ Lender storage
    /// @param params Parameters to liquidate an agent
    /// @return liquidatedValue Value of the liquidation returned to the liquidator
    function liquidate(ILender.LenderStorage storage $, ILender.RepayParams memory params)
        external
        returns (uint256 liquidatedValue)
    {
        (uint256 totalDelegation, uint256 totalDebt,,, uint256 health) = ViewLogic.agent($, params.agent);

        ValidationLogic.validateLiquidation(
            health,
            totalDelegation * $.emergencyLiquidationThreshold / totalDebt,
            $.liquidationStart[params.agent],
            $.grace,
            $.expiry
        );

        (uint256 assetPrice,) = IOracle($.oracle).getPrice(params.asset);
        uint256 maxLiquidation = ViewLogic.maxLiquidatable($, params.agent, params.asset);
        uint256 liquidated = params.amount > maxLiquidation ? maxLiquidation : params.amount;

        liquidated = BorrowLogic.repay(
            $,
            ILender.RepayParams({ agent: params.agent, asset: params.asset, amount: liquidated, caller: params.caller })
        );

        uint256 bonus = getBonus($, totalDelegation, totalDebt, params.agent, liquidated);

        liquidatedValue = (liquidated + bonus) * assetPrice / (10 ** $.reservesData[params.asset].decimals);
        if (totalDelegation < liquidatedValue) liquidatedValue = totalDelegation;

        IDelegation($.delegation).slash(params.agent, params.caller, liquidatedValue);

        emit Liquidate(params.agent, params.caller, params.asset, liquidated, liquidatedValue);
    }

    /// @dev Get the bonus for a liquidation in asset decimals up to the pro-rata bonus cap or
    /// credit ratio, whichever is smaller.
    /// @param $ Lender storage
    /// @param totalDelegation Total delegation of an agent
    /// @param totalDebt Total debt of an agent
    /// @param agent Agent address
    /// @param liquidated Liquidated amount in asset decimals
    /// @param bonus Bonus amount of asset
    function getBonus(
        ILender.LenderStorage storage $,
        uint256 totalDelegation,
        uint256 totalDebt,
        address agent,
        uint256 liquidated
    ) internal view returns (uint256 bonus) {
        if (totalDelegation > totalDebt) {
            uint256 elapsed = block.timestamp - ($.liquidationStart[agent] + $.grace);
            uint256 duration = $.expiry - $.grace;
            if (elapsed > duration) elapsed = duration;

            uint256 bonusPercentage = $.bonusCap * elapsed / duration;
            uint256 maxHealthyBonusPercentage = (totalDelegation - totalDebt) * 1e27 / totalDebt;
            if (bonusPercentage > maxHealthyBonusPercentage) bonusPercentage = maxHealthyBonusPercentage;

            bonus = liquidated * bonusPercentage / 1e27;
        }
    }
}
