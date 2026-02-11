// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISBold} from "../../interfaces/ISBold.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {IStabilityPool} from "../../external/IStabilityPool.sol";
import {Constants} from "../../libraries/helpers/Constants.sol";
import {Decimals} from "../../libraries/helpers/Decimals.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {QuoteLogic} from "./QuoteLogic.sol";
import {SpLogic} from "./SpLogic.sol";

/// @title SwapLogic
/// @notice Logic for swap execution.
library SwapLogic {
    using Math for uint256;

    /// @notice Swaps each SP collateral for $BOLD and returns total swapped amount.
    /// @param dst The unit in which the `src` is swapped.
    /// @param adapter The adapter to use to execute swap
    /// @param swapData The swap data.
    /// @param maxSlippage The minimum amount to receive after the swap.
    /// @return amount The quote amount with subtracted fees.
    function swap(
        address dst,
        address adapter,
        ISBold.SwapDataWithColl[] memory swapData,
        uint256 maxSlippage
    ) internal returns (uint256 amount) {
        // Execute swap for each Coll
        for (uint256 i = 0; i < swapData.length; i++) {
            if (swapData[i].balance == 0) continue;
            // Calculate minimum amount out in $BOLD
            uint256 minOut = calcMinOut(swapData[i].collInBold, maxSlippage);
            // Swap `src` for `bold`
            uint256 amountOut = _execute(adapter, swapData[i].addr, dst, swapData[i].balance, minOut, swapData[i].data);
            // Aggregate total amount of $BOLD received after swap
            amount += amountOut;
            // Emit on each swap
            emit ISBold.Swap(adapter, swapData[i].addr, dst, swapData[i].balance, amountOut, minOut);
        }
    }

    /// @notice Prepare swap data and claim collateral from protocol for each provided SP.
    /// @param bold Address of the underlying asset of the protocol.
    /// @param priceOracle Address of the price oracle.
    /// @param sps The available SPs within the protocol.
    /// @param swapData Input data for swap.
    /// @return swapDataWithColl Prepared data for swap.
    function prepareSwap(
        address bold,
        IPriceOracle priceOracle,
        ISBold.SP[] memory sps,
        ISBold.SwapData[] memory swapData
    ) internal returns (ISBold.SwapDataWithColl[] memory swapDataWithColl) {
        if (swapData.length > sps.length || swapData.length == 0) {
            revert ISBold.InvalidDataArray();
        }

        swapDataWithColl = new ISBold.SwapDataWithColl[](swapData.length);

        // Cycle through the input list of SP data for swap and find matching available SPs in protocol.
        for (uint256 i = 0; i < swapData.length; i++) {
            for (uint256 j = 0; j < sps.length; j++) {
                if (sps[j].sp == swapData[i].sp) {
                    // Claim collateral.
                    IStabilityPool(sps[j].sp).withdrawFromSP(0, true);

                    // If the input balance is not equal to the maximum claimed from SPs, the collateral will stay idle in this contract,
                    // until next swap utilizes the funds.
                    uint256 currentBalance = SpLogic._getCollBalanceSP(sps[j], true).balance;
                    uint256 balance = currentBalance < swapData[i].balance ? currentBalance : swapData[i].balance;

                    // Get collateral in $BOLD.
                    uint256 collInBold = QuoteLogic.getInBoldQuote(
                        priceOracle,
                        bold,
                        sps[j].coll,
                        balance,
                        ERC20(bold).decimals()
                    );
                    // Prepare data for swap by including details regarding collateral.
                    swapDataWithColl[i] = ISBold.SwapDataWithColl({
                        addr: sps[j].coll,
                        balance: balance,
                        collInBold: collInBold,
                        data: swapData[i].data
                    });
                }
            }

            // Revert if input SP address is not matching one of current SPs.
            if (swapDataWithColl[i].addr == address(0)) revert ISBold.InvalidDataArray();
        }
    }

    /// @notice Calculates minimum amount to be returned, based on the maximum slippage set.
    /// @param amount The amount to be swapped.
    /// @param maxSlippage The maximum slippage tolerance on swap in basis points.
    /// @return amount The amount returned by swap adapter after fees.
    function calcMinOut(uint256 amount, uint256 maxSlippage) internal pure returns (uint256) {
        return amount - amount.mulDiv(maxSlippage, Constants.BPS_DENOMINATOR);
    }

    /// @notice Deducts swap fee in BPS and reward for `caller` in BPS.
    /// @param amountOut The amount returned by swap adapter before fees.
    /// @param swapFeeBps The fee applied over the swap in basis points.
    /// @param rewardBps The reward for the `caller` applied over the swap in basis points.
    function applyFees(
        uint256 amountOut,
        uint256 swapFeeBps,
        uint256 rewardBps
    ) internal pure returns (uint256, uint256, uint256) {
        uint256 fee = amountOut.mulDiv(swapFeeBps, Constants.BPS_DENOMINATOR);
        uint256 reward = amountOut.mulDiv(rewardBps, Constants.BPS_DENOMINATOR);
        return (amountOut - fee - reward, fee, reward);
    }

    /// @notice Executes `call()` to swap `inAmount` of `src` token to `dst`.
    /// @param _src The unit that is swapped.
    /// @param _dst The unit in which the `src` is swapped.
    /// @param _inAmount The amount of `base` to be swapped.
    /// @param _minOut The minimum amount to receive after the swap.
    /// @param _swapData The swap data for 1inch router.
    function _execute(
        address _adapter,
        address _src,
        address _dst,
        uint256 _inAmount,
        uint256 _minOut,
        bytes memory _swapData
    ) private returns (uint256) {
        IERC20 dst = IERC20(_dst);
        // Get balance before the swap
        uint256 balance0 = dst.balanceOf(address(this));
        // Approve `_inAmount` for `adapter`
        IERC20(_src).approve(_adapter, _inAmount);
        // Execute swap
        (bool success, bytes memory data) = _adapter.call(_swapData);
        // Revert on failed swap
        if (!success) revert ISBold.ExecutionFailed(data);
        // Get balance after the swap
        uint256 balance1 = dst.balanceOf(address(this));
        // Get the amount received
        uint256 amountOut = balance1 - balance0;
        // Check if the amount received is equal or higher to the minimum
        if (amountOut < _minOut) revert ISBold.InsufficientAmount(amountOut);
        // Return decoded data
        return amountOut;
    }
}
