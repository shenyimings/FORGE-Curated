// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IDebtToken } from "../../interfaces/IDebtToken.sol";
import { IPrincipalDebtToken } from "../../interfaces/IPrincipalDebtToken.sol";

import { IRestakerRewardReceiver } from "../../interfaces/IRestakerRewardReceiver.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ILender } from "../../interfaces/ILender.sol";
import { ValidationLogic } from "./ValidationLogic.sol";
import { AgentConfiguration } from "./configuration/AgentConfiguration.sol";

/// @title BorrowLogic
/// @author kexley, @capLabs
/// @notice Logic for borrowing and repaying assets from the Lender
/// @dev Interest rates for borrowing are not based on utilization like other lending markets.
/// Instead the rates are based on a benchmark rate per asset set by an admin or an alternative
/// lending market rate, whichever is higher. Indexes representing the increase of interest over
/// time are pulled from an oracle. A separate interest rate is set by admin per agent which is
/// paid to the restakers that guarantee the agent.
library BorrowLogic {
    using SafeERC20 for IERC20;
    using AgentConfiguration for ILender.AgentConfigurationMap;

    /// @dev An agent has borrowed an asset from the Lender
    event Borrow(address indexed asset, address indexed agent, uint256 amount);

    /// @dev An agent, or someone on behalf of an agent, has repaid
    event Repay(
        address indexed asset,
        address indexed agent,
        uint256 principalRepaid,
        uint256 interestRepaid,
        uint256 restakerRepaid
    );

    /// @dev An agent has totally repaid their debt of an asset including all interests
    event TotalRepayment(address indexed agent, address indexed asset);

    /// @dev Realize interest before it is repaid by agents
    event RealizeInterest(address indexed asset, uint256 realizedInterest, address interestReceiver);

    /// @dev Trying to realize zero interest
    error ZeroRealization();

    /// @notice Borrow an asset from the Lender, minting a debt token which must be repaid
    /// @dev Interest debt token is updated before principal token is minted to bring index up to date.
    /// Restaker debt token is updated after so the new principal debt can be used in calculations
    /// @param $ Lender storage
    /// @param params Parameters to borrow an asset
    function borrow(ILender.LenderStorage storage $, ILender.BorrowParams memory params) external {
        ValidationLogic.validateBorrow($, params);

        ILender.ReserveData memory reserve = $.reservesData[params.asset];
        if (!$.agentConfig[params.agent].isBorrowing(reserve.id)) {
            $.agentConfig[params.agent].setBorrowing(reserve.id, true);
        }

        IVault(reserve.vault).borrow(params.asset, params.amount, params.receiver);

        IDebtToken(reserve.interestDebtToken).update(params.agent);
        IPrincipalDebtToken(reserve.principalDebtToken).mint(params.agent, params.amount);
        IDebtToken(reserve.restakerDebtToken).update(params.agent);

        emit Borrow(params.agent, params.asset, params.amount);
    }

    /// @notice Repay an asset, burning the debt token and/or paying down interest
    /// @dev Only the amount owed or specified will be taken from the repayer, whichever is lower.
    /// Interest debt is paid first as the amount accrued is based on current principal debt, restaker
    /// debt is paid last as the future rate is calculated based on the resulting principal debt.
    /// @param $ Lender storage
    /// @param params Parameters to repay a debt
    /// @return _repaid Actual amount repaid
    function repay(ILender.LenderStorage storage $, ILender.RepayParams memory params)
        external
        returns (uint256 _repaid)
    {
        ILender.ReserveData memory reserve = $.reservesData[params.asset];
        IDebtToken(reserve.interestDebtToken).update(params.agent);
        IDebtToken(reserve.restakerDebtToken).update(params.agent);
        uint256 principalDebt = IERC20(reserve.principalDebtToken).balanceOf(params.agent);
        uint256 restakerDebt = IERC20(reserve.restakerDebtToken).balanceOf(params.agent);
        uint256 interestDebt = IERC20(reserve.interestDebtToken).balanceOf(params.agent);
        uint256 principalRepaid;
        uint256 restakerRepaid;
        uint256 interestRepaid;

        /// Maturity order of repayment is principal, restaker, then interest
        if (params.amount > principalDebt) {
            principalRepaid = principalDebt;
            if (params.amount > principalDebt + restakerDebt) {
                restakerRepaid = restakerDebt;
                if (params.amount > principalDebt + restakerDebt + interestDebt) {
                    interestRepaid = interestDebt;
                } else {
                    interestRepaid = params.amount - principalDebt - restakerDebt;
                }
            } else {
                restakerRepaid = params.amount - principalDebt;
            }
        } else {
            principalRepaid = params.amount;
        }

        if (principalRepaid > 0) {
            IPrincipalDebtToken(reserve.principalDebtToken).burn(params.agent, principalRepaid);
            IERC20(params.asset).safeTransferFrom(params.caller, address(this), principalRepaid);
            IERC20(params.asset).forceApprove(reserve.vault, principalRepaid);
            IVault(reserve.vault).repay(params.asset, principalRepaid);
        }

        if (restakerRepaid > 0) {
            restakerRepaid = IDebtToken(reserve.restakerDebtToken).burn(params.agent, restakerRepaid);
            IERC20(params.asset).safeTransferFrom(params.caller, reserve.restakerInterestReceiver, restakerRepaid);
            IRestakerRewardReceiver(reserve.restakerInterestReceiver).distributeRewards(params.agent, params.asset);
        }

        if (interestRepaid > 0) {
            uint256 realizedInterestRepaid;
            if (reserve.realizedInterest > 0) {
                /// Repay realized interest directly back to vault instead of to fee auction
                realizedInterestRepaid =
                    interestRepaid < reserve.realizedInterest ? interestRepaid : reserve.realizedInterest;

                $.reservesData[params.asset].realizedInterest -= realizedInterestRepaid;
                IERC20(params.asset).safeTransferFrom(params.caller, address(this), realizedInterestRepaid);
                IERC20(params.asset).forceApprove(reserve.vault, realizedInterestRepaid);
                IVault(reserve.vault).repay(params.asset, realizedInterestRepaid);
            }

            interestRepaid = IDebtToken(reserve.interestDebtToken).burn(params.agent, interestRepaid);
            if (interestRepaid > realizedInterestRepaid) {
                IERC20(params.asset).safeTransferFrom(
                    params.caller, reserve.interestReceiver, interestRepaid - realizedInterestRepaid
                );
            }
        }

        if (
            IERC20(reserve.principalDebtToken).balanceOf(params.agent) == 0
                && IERC20(reserve.restakerDebtToken).balanceOf(params.agent) == 0
                && IERC20(reserve.interestDebtToken).balanceOf(params.agent) == 0
        ) {
            $.agentConfig[params.agent].setBorrowing(reserve.id, false);
            emit TotalRepayment(params.agent, params.asset);
        }

        _repaid = principalRepaid + interestRepaid + restakerRepaid;

        emit Repay(params.agent, params.asset, principalRepaid, interestRepaid, restakerRepaid);
    }

    /// @notice Realize the interest before it is repaid by borrowing from the vault
    /// @param $ Lender storage
    /// @param params Parameters for realizing interest
    /// @return realizedInterest Actual realized interest
    function realizeInterest(ILender.LenderStorage storage $, ILender.RealizeInterestParams memory params)
        external
        returns (uint256 realizedInterest)
    {
        ILender.ReserveData memory reserve = $.reservesData[params.asset];
        uint256 _maxRealization = maxRealization($, params.asset);
        if (_maxRealization == 0) revert ZeroRealization();

        realizedInterest = params.amount > _maxRealization ? _maxRealization : params.amount;
        $.reservesData[params.asset].realizedInterest += realizedInterest;
        IVault(reserve.vault).borrow(params.asset, realizedInterest, reserve.interestReceiver);
        emit RealizeInterest(params.asset, realizedInterest, reserve.interestReceiver);
    }

    /// @notice Calculate the maximum interest that can be realized
    /// @param $ Lender storage
    /// @param _asset Asset to calculate max realization for
    /// @return maxRealization Maximum interest that can be realized
    function maxRealization(ILender.LenderStorage storage $, address _asset) internal view returns (uint256) {
        ILender.ReserveData memory reserve = $.reservesData[_asset];
        uint256 totalInterest = IERC20(reserve.interestDebtToken).totalSupply();
        uint256 reserves = IVault(reserve.vault).availableBalance(_asset);
        uint256 _maxRealization = 0;
        if (totalInterest > reserve.realizedInterest) {
            _maxRealization = totalInterest - reserve.realizedInterest;
        }
        if (reserves < _maxRealization) {
            _maxRealization = reserves;
        }
        return _maxRealization;
    }
}
